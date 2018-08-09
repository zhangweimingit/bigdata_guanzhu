local log = ngx.log
local ERR = ngx.ERR
local new_timer = ngx.timer.at
local dict = ngx.shared.dict
local redis = require "resty.redis" 
local cjson = require "cjson"

--分割字符串
function split(pString, pPattern)
   local Table = {}  -- NOTE: use {n = 0} in Lua-5.0
   local fpat = "(.-)" .. pPattern
   local last_end = 1
   local s, e, cap = pString:find(fpat, 1)
   while s do
      if s ~= 1 or cap ~= "" then
     table.insert(Table,cap)
      end
      last_end = e+1
      s, e, cap = pString:find(fpat, last_end)
   end
   if last_end <= #pString then
      cap = pString:sub(last_end)
      table.insert(Table, cap)
   end
   return Table
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
    dict:set("redis_ip",redis_ip)
    log(ngx.INFO,"redis_ip:",redis_ip)
end

 
update_ips_fun = function(premature)
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

local function process_rules()

	--连接redis server
    local redis_cli = redis.new() 
    redis_cli:set_timeout(60000)
    local ok, err = redis_cli:connect(dict:get("redis_ip"), 6379) 
    if not ok then 
        log(ngx.ERR,"connect redis error:",err)
        return 
    end 
    --local red, err = redis_cli:auth("foobared")
    --if not red then
    --    log(ngx.ERR,"failed to authenticate: ", err)
    --    return
    --end

	--获取当前使用的目录
	local dir, err = redis_cli:get("last-used-dir")
	if not dir then
		log(ngx.ERR,"err get") 
		return
	end 

	if dir == ngx.null then --表示当前日志还没有被切分
		log(ngx.NOTICE,"LOG is not splited") 
		return
	end 

	--从队列中获取一个待处理的规则,获取的是规则key
    local rule_key, err = redis_cli:lpop("rule_queue")

    if not rule_key then  
        log(ngx.ERR,"err lpop") 
        return
    end 

    if rule_key ~= ngx.null then
        local resp, err = redis_cli:hgetall(rule_key)--根据key获取规则内容
        if not resp then  
            log(ngx.ERR,"err hgetall") 
            return
        end 

		local count = 0
        local wait_to_redis = {}
        local rule = redis_cli:array_to_hash(resp)
		local places = split(rule.place,',')
		
		for i=1,#places do
			local province_city = split(places[i],'-')
			file = io.open("/home/bigdata/" .. dir .."/" .. province_city[1] ..".txt","r");
			if file then  
				for line in file:lines() do
					local t = split(line,'\t')
					local begin_sex, end_sex =string.find(rule.sex,t[2],1,true)--首先匹配性别
					if begin_sex then  
						local begin_place, end_place =string.find(rule.place,t[3] .. "-" .. t[4],1,true)--匹配省份城市
						if begin_place then  
							local love_score = split(t[6],',')--分割兴趣爱好
							for k=1, #love_score do  --匹配每个爱好
								local love = split(love_score[k],':')--去掉每个爱好后面的分数
								local begin_love, ends_love =string.find(rule.interest,love[1],1,true)
								if begin_love then  
									local zdd_arg = {}
									zdd_arg.arg1 = t[1] .. "guanzhu"
									zdd_arg.arg2 = rule.priority
									zdd_arg.arg3 = rule.guanzhu
									table.insert(wait_to_redis,zdd_arg)
									count = count + 1
									break--匹配到一个就可以把公众号加入到该mac
								end
							end 
						end
					end
					
					if count >= 1000 then
						redis_cli:init_pipeline()
						for j=1, #wait_to_redis do  --匹配每个爱好
							redis_cli:zadd(wait_to_redis[j].arg1,wait_to_redis[j].arg2,wait_to_redis[j].arg3)
						end
						redis_cli:commit_pipeline()
						wait_to_redis = {}
						count = 0
					end
				end
				file:close()
			end 
		end
        

        if count > 0 then
            redis_cli:init_pipeline()
            for i=1, #wait_to_redis do 
                redis_cli:zadd(wait_to_redis[i].arg1,wait_to_redis[i].arg2,wait_to_redis[i].arg3)
            end
            redis_cli:commit_pipeline()
            wait_to_redis = {}
            count = 0
        end

        --保存已完成规则的key
        local resp, err =  redis_cli:sadd("completed_rule",rule_key)
        if not resp then  
            log(ngx.ERR,"err rule sadd") 
            return
        end 
        log(ngx.NOTICE,"completed_rule ",rule_key) 
    end 
end

process_rules_fun = function(premature)
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

    ori_file = io.open("/home/bigdata/1.txt" ,"r");--先打开顺网文件,确保文件存在
    if not ori_file then  
        log(ngx.ERR,"open /home/bigdata/1.txt failed") 
		return
    end 
	
    local redis_cli = redis.new() 
    redis_cli:set_timeout(60000)
    local ok, err = redis_cli:connect(dict:get("redis_ip"), 6379) 
    if not ok then 
        log(ngx.ERR,"connect redis error:",err)
        return 
    end 
    --local red, err = redis_cli:auth("foobared")
    --if not red then
    --    log(ngx.ERR,"failed to authenticate: ", err)
    --    return
    --end
 
    local resp, err = redis_cli:get("last-modified")--获取顺网数据最后一次修改时间
    if not resp then  
        log(ngx.ERR,"err get") 
        return
    end 

	local stat = io.popen("stat -c %Y /home/bigdata/1.txt")--获取顺网数据最后一次修改时间
	local last_modified = stat:read()
	if resp ~= last_modified then--需要重新分割文件

		local resp, err = redis_cli:get("last-used-dir")--获取当前使用的目录
		if not resp then  
			log(ngx.ERR,"err get") 
			return
		end 
		
		local dir = ""
		if resp ~= "split1" then --/home/bigdata/split1/江苏省.txt 北京市.txt
			dir = "split1"
		else
			dir = "split2"
		end
		
		local cmd_rm = os.execute("rm /home/bigdata/" .. dir .. "/*.txt")--先删除该目录下所有文件
		
		local province_files = {}
		for line in ori_file:lines() do
			local t = split(line,'\t')
			
			if not province_files[t[3]] then--打开相应省份的txt文件
			    tmpfile = io.open("/home/bigdata/" .. dir .."/" .. t[3] ..".txt" ,"w+");
				if not tmpfile then  
					log(ngx.ERR,"/home/bigdata/" .. dir .."/" .. t[3] ..".txt") 
					return
				end 
				province_files[t[3]] = tmpfile
			end
			
			province_files[t[3]]:write(line .. "\n")
		end
		
		local resp, err = redis_cli:set("last-used-dir",dir)--获取当前使用的目录
		if not resp then  
			log(ngx.ERR,"err set") 
			return
		end 
		
		local resp, err = redis_cli:set("last-modified",last_modified)
		if not resp then  
			log(ngx.ERR,"err set") 
			return
		end 
		
		for i=1,#province_files do
			province_files[i]:close()
		end
	end
end
split_file_fun = function(premature)
    if not premature then
        log(ngx.INFO,"timer split_file_fun....")
        split_file()
        local ok, err = new_timer(60, split_file_fun)
        if not ok then
            log(ngx.ERR, "failed to create timer: ", err)
            return
        end
    end
end

local function main()

    if 0 == ngx.worker.id() then
	    --更新redis server ip地址
        local ok, err = new_timer(1, update_ips_fun)
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
    end

    --处理广告商下发的规则
    local ok, err = new_timer(5, process_rules_fun)
    if not ok then
        ngx.log(ngx.ERR, "failed to create a timer: ", err)
        return
    end
end

main()
 