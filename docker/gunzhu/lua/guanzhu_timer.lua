local log = ngx.log
local new_timer = ngx.timer.at
local dict = ngx.shared.dict
local redis = require "resty.redis-util" --https://github.com/anjia0532/lua-resty-redis-util

---去掉文件名后缀
function getFileName(str)
    local idx = str:match(".+()%.%w+$")
    if(idx) then
        return str:sub(1, idx-1)
    else
        return str
    end
end

---获得文件扩展名
function getExtension(str)
    return str:match(".+%.(%w+)$")
end

--获得rootpath下以gz为扩展名的文件列表
function getpaths(rootpath)
    pathes =  {}
    local file = io.popen("ls " .. rootpath)
    if file then  
        for entry in file:lines() do
            if getExtension(entry) == "gz" and string.find(entry,"ak_user_tag",1,true) then
                table.insert(pathes, entry)
            end
        end
    end
    return pathes
end

--分割字符串
function split( str,reps )
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function ( w )
        table.insert(resultStrList,w)
    end)
    return resultStrList
end

local function getip(service_name)
    local container = os.getenv(service_name)
    local cmd = [[ping ]] .. container .. [[ -c1 | grep from | awk '{ print $4 }'|cut -d: -f1]]
    local t= io.popen(cmd)
    local a = t:read("*all")
    return string.sub(a, 1, -2)
end

local function up_ips()
    local redis_ip = getip("REDIS-SERVER")
    local guanzhu_ip = getip("GUANZHU")
    dict:set("redis_ip",redis_ip)
    dict:set("guanzhu_ip",guanzhu_ip)
    log(ngx.INFO,"redis_ip:",redis_ip," guanzhu_ip:",guanzhu_ip)
end

--更新redis-server的ip地址
local function update_ips_fun(premature)
    if not premature then
        log(ngx.INFO,"up_ips....")
        up_ips()
        local ok, err = new_timer(10, update_ips_fun)
        if not ok then
            log(ngx.ERR, "failed to create timer: ", err)
            return
        end
    end
end

--开始匹配规则
local function process_rules()

    local redis_cli = redis:new({ host=dict:get("redis_ip") });

    --获取当前使用的目录
    local dir, err = redis_cli:get("last-used-dir")
    if not dir then
        log(ngx.INFO,"LOG is not splited,wait..") 
        return
    end 

    --从队列中获取一个待处理的规则,获取的是规则key
    local rule_key, err = redis_cli:lpop("rule_queue")
    if not rule_key then  
        log(ngx.INFO,"no rule is ready to process") 
        return
    end 

    --根据key获取规则内容
    local resp, err = redis_cli:hgetall(rule_key)
    if not resp then  
        log(ngx.INFO,"key has been deleted ",rule_key) 
        return
    end 

    local count = 0
    local total = 0
    local rule = redis_cli:array_to_hash(resp)
    local places = split(rule.place,',')
    
    for i=1,#places do
        local grep
        if rule.interest == "不限"  then
            grep = string.format([[cat %s/%s]],dir,places[i])
        else
            grep = string.format([[grep -E "%s" %s/%s]],string.gsub(rule.interest,",","|"),dir,places[i])--根据省份，去匹配相应的文件
        end

        if rule.sex == "不限" then
            grep = string.format([[%s | awk 'BEGIN{FS="\t"} {print $1}']],grep)--输出匹配的mac
        else
            grep = string.format([[%s | awk 'BEGIN{FS="\t"} {if($2=="%s"){ print $1 } }']],grep,rule.sex)
        end

        local file = io.popen(grep)
        if file then  
            for mac in file:lines() do
                if count == 0 then
                    redis_cli:init_pipeline()
                    redis_cli:zadd(mac .. "guanzhu",rule.priority,rule_key .. "," .. rule.guanzhu)
                    count = count + 1
                elseif count >= 500 then
                    redis_cli:commit_pipeline()
                    total = total + count
                    count = 0
                    
                    if dict:get(rule_key) == "deleted" then
                        redis_cli:sadd("completed_rule",rule_key)
                        dict:set(rule_key,nil)
                        return
                    end
                else
                    redis_cli:zadd(mac .. "guanzhu",rule.priority,rule_key .. "," .. rule.guanzhu)
                    count = count + 1
                end
            end
            file:close()
        end
    end

    if count > 0 then
        redis_cli:commit_pipeline()
        total = total + count
        count = 0
    end

    redis_cli:init_pipeline()
    redis_cli:set(rule_key .. "match_count",total)--保存该规则匹配到的mac数量
    redis_cli:sadd("completed_rule",rule_key)--保存已完成匹配的规则的key
    redis_cli:commit_pipeline()

    log(ngx.NOTICE,"completed_rule ",rule_key) 
end

local function process_rules_fun(premature)
    if not premature then
        log(ngx.INFO,"timer process_rules....")
        process_rules()
        local ok, err = new_timer(5, process_rules_fun)
        if not ok then
            log(ngx.ERR, "failed to create timer: ", err)
            return
        end
    end
end
 
local function split_file()

    local rootpath = "/home/bigdata/shunwang"
    local paths = getpaths(rootpath)--获取目录下所有以gz为扩展名的文件

    if #paths == 0 then
        return
    end

    local changtime = 0
    local filename = ""
    for i=1,#paths do
        local stat = io.popen("stat -c %Y " .. rootpath .. "/" .. paths[i])--获取修改时间
        local last_modified = tonumber(stat:read())
        if last_modified > changtime then
            changtime = last_modified
            filename = paths[i]
        end
    end
    
    local redis_cli = redis:new({ host=dict:get("redis_ip") });

    local resp, err = redis_cli:get("changtime" .. filename)--时间在变化，说明文件还在传输
    if not resp or tonumber(resp) ~= changtime then
        redis_cli:set("changtime" .. filename,changtime)
        return
    end

    log(ngx.NOTICE,"spliting begin.................") 
    local dir = ""
    local resp, err = redis_cli:get("last-used-dir")--获取当前使用的目录
    if resp ~= "/home/bigdata/split1" then --/home/bigdata/split1/江苏-南京.txt 北京-北京.txt
        dir = "/home/bigdata/split1"
    else
        dir = "/home/bigdata/split2"
    end

    os.execute(string.format([[rm -f %s/*]],dir))--删除该目录下所有文件

    local result = os.execute(string.format([[cd %s && gunzip %s/%s]],rootpath,rootpath,filename))--解压
    if not result then
        log(ngx.ERR, "failed to gunzip ", filename)
        os.execute(string.format([[rm -f %s/%s]],rootpath,filename))
        os.execute(string.format([[rm -f %s/%s]],rootpath,getFileName(filename)))
        return
    end

    os.execute(string.format([[mv %s/%s %s/全国]],rootpath,getFileName(filename),dir))
    os.execute(string.format([[ awk 'BEGIN{FS="\t"} {if($3!="\\N" && $4!="\\N"){print $0 >> "%s/"$3"-"$4} if($3!="\\N"){print $0 >> "%s/"$3}}' %s/全国]],dir,dir,dir))
    
    redis_cli:init_pipeline()
    redis_cli:set("last-used-dir",dir)
    redis_cli:del("changtime" .. filename)
    redis_cli:commit_pipeline()
    log(ngx.NOTICE,"spliting end")
end

local function split_file_fun(premature)
    if not premature then
        log(ngx.INFO,"timer split_file_fun....")
        split_file()
        local ok, err = new_timer(10, split_file_fun)
        if not ok then
            log(ngx.ERR, "failed to create timer: ", err)
            return
        end
    end
end

local function process_del_rules()
    --连接redis server
    local redis_cli = redis:new({ host=dict:get("redis_ip") });

    --从队列中获取一个待处理的规则,获取的是规则key
    local rule_key, err = redis_cli:lindex("rule_queue_del",0)

    if not rule_key then  
        log(ngx.INFO,"no rule is ready to process") 
        return
    end 

    local resp, err =  redis_cli:sismember("completed_rule",rule_key)
    if resp ~= 1 then  
        log(ngx.NOTICE,"wait to del") 
        return
    end

    redis_cli:init_pipeline()
    redis_cli:del(rule_key .. "match_count")
    redis_cli:srem("all_rule",rule_key)
    redis_cli:srem("completed_rule",rule_key)
    redis_cli:lpop("rule_queue_del")
    redis_cli:commit_pipeline()
    log(ngx.NOTICE,"completed delete rule ",rule_key) 

end
local function process_del_rules_fun(premature)
    if not premature then
        log(ngx.INFO,"timer process_del_rules_fun....")
        process_del_rules()
        local ok, err = new_timer(5, process_del_rules_fun)
        if not ok then
            log(ngx.ERR, "failed to create timer: ", err)
            return
        end
    end
end

local function main()

    if 0 == ngx.worker.id() then
    
        --切分文件时需要，假设正在读取split1下文件，那么顺网更新数据时，将新切分的文件放在split2下
        os.execute("mkdir /home/bigdata/split1")
        os.execute("mkdir /home/bigdata/split2")
        --更新redis server ip地址
        local ok, err = new_timer(0, update_ips_fun)
        if not ok then
            ngx.log(ngx.ERR, "failed to create a timer: ", err)
            return
        end
        
        --按省份切割顺网给的原始数据文件
        local ok, err = new_timer(2, split_file_fun)
        if not ok then
            ngx.log(ngx.ERR, "failed to create a timer: ", err)
            return
        end
        
            --删除广告商下发的规则
        local ok, err = new_timer(5, process_del_rules_fun)
        if not ok then
            ngx.log(ngx.ERR, "failed to create a timer: ", err)
            return
        end
    end

    --处理广告商下发的规则
    local ok, err = new_timer(5, process_rules_fun)
    if not ok then
        ngx.log(ngx.ERR, "failed to create a timer: ", err)
        return
    end
end

main()