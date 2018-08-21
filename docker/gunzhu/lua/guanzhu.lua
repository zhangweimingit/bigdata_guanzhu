local log = ngx.log
local dict = ngx.shared.dict
local cjson = require "cjson"
local redis = require "resty.redis-util" --https://github.com/anjia0532/lua-resty-redis-util
local redis_cli = redis:new({ host=dict:get("redis_ip") });
cjson.encode_empty_table_as_object(false)

--分割字符串
function split( str,reps )
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function ( w )
        table.insert(resultStrList,w)
    end)
    return resultStrList
end

--获取http的body
local function get_client_body()
    ngx.req.read_body()    
    local body_data = ngx.req.get_body_data()
    if not body_data then 
        local tmp_body_fd = io.open(tostring(ngx.req.get_body_file()), 'r')
        if not tmp_body_fd then
            body_data = nil
            return body_data
        end
        body_data = tmp_body_fd:read("*a") 
        tmp_body_fd:close()
        if not body_data then
            ngx.log(ngx.ERR, 'post temporary file read failure! Remote IP: ' .. tostring(ngx.var.remote_addr))
            body_data = nil
        end
    end
    if body_data == nil then
        body_data = {}
    end
    return body_data
end


local function main()
    --路由器根据mac查询公众号
    local m,err = ngx.re.match(ngx.var.request_uri,"^/guanzhu/([^/]+)/weixin/client","jo")
    local method = ngx.req.get_method()
    if m and method == "GET"  then
        log(ngx.INFO,"received query message!!!")
        local mac = ngx.var.arg_mac
        if not mac then
            log(ngx.ERR,"Parameter error")
            local t = {}
            t.code = 403
            t.status = "error"
            t.message = "no mac parameter"
            t.guanzhu = {}
            ngx.send_headers()    
            ngx.print(cjson.encode(t))
            ngx.flush(true)
            return 
        end

        --获取所有公众号
        local guanzhus, err = redis_cli:zrevrange(mac .. "guanzhu", 0, -1)
        if not guanzhus then  -- no key,no element
            local t = {}
            t.code = 200
            t.messsage = "no guanzhu"
            t.status = "success"
            t.guanzhu = {}
            ngx.send_headers()    
            ngx.print(cjson.encode(t))
            ngx.flush(true) 
            return
        end

        
        --测试生成公众号对应的规则key是否还存在，不存在则删除公众号
        redis_cli:init_pipeline()
        for i = 1, #guanzhus do
            redis_cli:exists(split(guanzhus[i],',')[1])--分割后,[1]为规则key,[2]为公众号     
        end

        local results, err = redis_cli:commit_pipeline()
        if not results then
            log(ngx.ERR,"failed to commit the pipelined requests: ", err)
            return
        end
        
        local t = {}
        t.guanzhu = {}

        redis_cli:init_pipeline()
        for i, res in ipairs(results) do
            if type(res) == "number" then
                if res == 1 then
                    table.insert(t.guanzhu,split(guanzhus[i],',')[2])
                else
                    redis_cli:zrem(guanzhus[i])
                end
            end
        end
        redis_cli:commit_pipeline()
        
        t.code = 200
        t.messsage = "ok"
        t.status = "success"
        ngx.send_headers()    
        ngx.print(cjson.encode(t))
        ngx.flush(true) 
        return 
    end     

    --Receiving rules
    local m,err = ngx.re.match(ngx.var.request_uri,"^/guanzhu/([^/]+)/weixin/rules","jo")
    local method = ngx.req.get_method()
    if m and ( method == "POST" or method == "GET" or method == "DELETE") then
        log(ngx.INFO,"received rules!!!")
        local rule_id = ngx.var.arg_id
        if not rule_id then
            log(ngx.ERR,"Parameter error")
            local t = {}
            t.code = 403
            t.status = "fail"
            t.message = "Parameter error"
            ngx.send_headers()    
            ngx.print(cjson.encode(t))
            ngx.flush(true)
            return 
        end
        if method == "POST" then --下发规则
            local data = get_client_body()
            if not data then
                log(ngx.ERR,"err rule no body data")
                local t = {}
                t.code = 403
                t.status = "fail"
                t.message = "rule no body data"
                ngx.send_headers()    
                ngx.print(cjson.encode(t))
                ngx.flush(true)
                return 
            end
            local t = cjson.decode(data)
            local sex = t.sex
            local place = t.place
            local priority = t.priority
            local interest = t.interest
            local guanzhu = t.guanzhu
    
            --保存规则
            local resp, err =  redis_cli:hmset("rule" .. rule_id,"id",rule_id,"sex",sex,"place",place,"priority",priority,"interest",interest,"guanzhu",guanzhu)
            if not resp then  
                log(ngx.ERR,"hmset ",err) 
                return
            end 
    
            --保存规则的key
            local resp, err =  redis_cli:sadd("all_rule","rule" .. rule_id)
            if not resp then  
                log(ngx.ERR,"sadd ",err) 
                return
            end 
    
            --将待处理的规则的key入队列
            local resp, err =  redis_cli:rpush("rule_queue","rule" .. rule_id)
            if not resp then  
                log(ngx.ERR,"rpush",err) 
                return
            end 
    
            local t = {}
            t.code = 200
            t.messsage = "send rule success"
            t.status = "success"
            ngx.send_headers()    
            ngx.print(cjson.encode(t))
            ngx.flush(true)
            return
        end
        
        if method == "GET" then --查询规则当前是否处理完成
            local match_count, err = redis_cli:get("rule" .. rule_id .. "match_count")
            local resp1, err1 =  redis_cli:sismember("completed_rule","rule" .. rule_id)
            local resp2, err2 =  redis_cli:exists("rule" .. rule_id)

            local t = {}
            t.code = 200
            t.status = "success"
            if resp2 ~= 1 then  --查询规则是否存在
                t.messsage = "non-existent"
                t.match_count = 0
            elseif resp1 ~= 1 then --查询规则是否匹配完成
                t.messsage = "unfinished"
                t.match_count = 0
            else
                t.match_count = match_count
                t.messsage = "finished"
            end

            ngx.send_headers()    
            ngx.print(cjson.encode(t))
            ngx.flush(true)
            return
        end

        if method == "DELETE" then --删除规则
            local resp, err =  redis_cli:exists("rule" .. rule_id)
            if resp ~= 1 then  
                local t = {}
                t.code = 403
                t.messsage = "no this rule"
                t.status = "failed"
                ngx.send_headers()    
                ngx.print(cjson.encode(t))
                ngx.flush(true)
                return
            end

            redis_cli:del("rule" .. rule_id)
            dict:set("rule" .. rule_id,"deleted")

            --将待处理的规则的key入队列
            local resp, err =  redis_cli:rpush("rule_queue_del","rule" .. rule_id)
            if not resp then  
                log(ngx.ERR,"rpush",resp) 
                return
            end 
    
            local t = {}
            t.code = 200
            t.messsage = "del rule success"
            t.status = "success"
            ngx.send_headers()    
            ngx.print(cjson.encode(t))
            ngx.flush(true)
            return
        end
    end

    local m,err = ngx.re.match(ngx.var.request_uri,"^/version","jo")
    local method = ngx.req.get_method()
    if m and method == "GET"  then
        local detail = ngx.var.arg_detail
        local t = {}
        t.code = 200
        t.status = "success"
        t.data = {}
        t.data.service_name = "guanzhu"
        t.data.version = "1.0.0"
        
        if detail == "yes" then
            t.data.ip = dict:get("guanzhu_ip")
            t.data.port = 80
        end
        
        ngx.send_headers()    
        ngx.print(cjson.encode(t))
        ngx.flush(true)
        return
    end

    local m,err = ngx.re.match(ngx.var.request_uri,"^/guanzhu/([^/]+)/status","jo")
    local method = ngx.req.get_method()
    if m and method == "GET" then
        local t = {}
        t.code = 200
        t.status = "success"
        t.data = {}
        t.data.run = "ok"
        ngx.send_headers()    
        ngx.send_headers()    
        ngx.print(cjson.encode(t))
        ngx.flush(true)
        return
    end

    log(ngx.ERR,"wrong url:",ngx.var.request_uri)
    local t = {}
    t.code = 403
    t.status = "fail"
    t.message = "not support url!!"
    ngx.send_headers()    
    ngx.print(cjson.encode(t))
    ngx.flush(true) 
end

main()
