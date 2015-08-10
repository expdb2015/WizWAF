cjson = require "cjson"

function debuglog(...)
    local log_table = {}
    for i = 1, select("#", ...) do
        log_table[i] = select(i, ...)
    end
    ngx.log(ngx.ERR, "[NGINX-LUA-DS-WAF-DEBUG] ", cjson.encode(log_table))
end

function ngxlog(...)
    ngx.log(ngx.ERR, "[NGINX-LUA-DS-WAF] ", ...)
end

local redis = require "resty.redis_iresty"
red = redis:new()
rabbitmq = require "resty.rabbitmqstomp"


fd_log = io.open("/var/log/waf/waf.log","ab")


function split(str, sep)
    local fields = {}
    str:gsub("[^"..sep.."]+", function(c) fields[#fields+1] = c end)
    return fields
end


function get_value_from_cache_or_redis(key)
    local value = ngx.shared.redis_cache:get(key)
    if value then
        return value
    else
        local res, err = red:get(key)
        if res then
            ngx.shared.redis_cache:safe_set(key, res, 600)
            return res
        else
            ngxlog("Can't get " .. key .. " from redis: ", err)
        end
    end
end


function get_smembers_from_cache_or_redis(key)
    local str = ngx.shared.redis_cache:get(key)
    if str then
        return split(str, "|||||")
    else
        local res, err = red:smembers(key)
        if res then
            local str = ""
            for key, value in ipairs(res) do
                if key == 1 then
                    str = value
                else
                    str = str .. "|||||" .. value
                end
            end
            ngx.shared.redis_cache:safe_set(key, str, 600)
            return res
        else
            ngxlog("Can't get " .. key .. " from redis: ", err)
        end
    end
end


function dswaf_output()
    ngx.status = ngx.HTTP_FORBIDDEN
    ngx.header.content_type = 'text/html'
    ngx.say([[
<!DOCTYPE html>
<html lang="zh-CN">
<head>
	<meta charset="utf-8">
</head>
<body style="width:100%;height:100%;background:#0066cc;">
	<h1 style="color:#FFF;text-align:center;">You have been blocked by NGINX-LUA-DS-WAF.</h1>
</body>
</html>
]])
    ngx.exit(ngx.HTTP_FORBIDDEN)
end


