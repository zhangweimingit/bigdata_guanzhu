local log = ngx.log
local dict = ngx.shared.dict
local cjson = require "cjson"
local redis = require "resty.redis" 

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
    --路由器查询公众号
    local m,err = ngx.re.match(ngx.var.request_uri,"^/guanzhu/([^/]+)/weixin/mac","jo")
    local method = ngx.req.get_method()
    if m and method == "GET"  then
        log(ngx.INFO,"received Router query message!!!")
        local data = get_client_body()
        if not data then
            log(ngx.ERR,"err Router no body data")
            local t = {}
            t.code = 403
            t.status = "fail"
            t.message = "query no body data"
            t.guanzhu = 0
            ngx.send_headers()    
            ngx.print(cjson.encode(t))
            ngx.flush(true)
            return 
        end

        --获取路由器上传的mac
        local t = cjson.decode(data)
        local mac = t.mac

        --获取优先级最高的公众号
        local resp, err = redis_cli:zrevrange(mac .. "guanzhu", 0,0)
        if not resp then  
            log(ngx.ERR,"err Router zrevrange") 
            return
        end  

        if resp[1] then
            log(ngx.INFO,"get result") 
            local t = {}
            t.code = 200
            t.messsage = "query ok!"
            t.status = "success"
            t.guanzhu = resp[1]
            ngx.send_headers()    
            ngx.print(cjson.encode(t))
            ngx.flush(true) 
            
            --该公众号不再推送给该mac，所以删除
            local resp, err = redis_cli:zrem(mac .. "guanzhu", resp[1])
            if not resp then  
                log(ngx.ERR,"err Router zrem") 
            end
            return 
        end 
        
        local t = {}
        t.code = 200
        t.messsage = "no guanzhu"
        t.status = "success"
        t.guanzhu = 0
        ngx.send_headers()    
        ngx.print(cjson.encode(t))
        ngx.flush(true) 
        return 
    end     

    --Receiving rules
    local m,err = ngx.re.match(ngx.var.request_uri,"^/guanzhu/([^/]+)/weixin/rules","jo")
    local method = ngx.req.get_method()
    if m and method == "POST"  then
        log(ngx.INFO,"received rules!!!")
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
        local rule_id = t.id
        local sex = t.sex
        local place = t.place
        local priority = t.priority
        local interest = t.interest
        local guanzhu = t.guanzhu

        --保存规则
        local resp, err =  redis_cli:hmset("rule" .. rule_id,"id",rule_id,"sex",sex,"place",place,"priority",priority,"interest",interest,"guanzhu",guanzhu)
        if not resp then  
            log(ngx.ERR,"err rule hmset") 
            return
        end 

        --保存规则的key
        local resp, err =  redis_cli:sadd("all_rule","rule" .. rule_id)
        if not resp then  
            log(ngx.ERR,"err rule sadd") 
            return
        end 

        --将待处理的规则的key入队列
        local resp, err =  redis_cli:rpush("rule_queue","rule" .. rule_id)
        if not resp then  
            log(ngx.ERR,"err rule rpush") 
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
