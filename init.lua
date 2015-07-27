function ngxlog(...)
    ngx.log(ngx.ERR, "[NGINX-LUA-DS-WAF] ", ...)
end

local redis = require "resty.redis_iresty"
red = redis:new()

fd_log = io.open("/var/log/waf/waf.log","ab")

function redis_get(key, default_value)
    local res, err = red:get(key)
    if not res then
        ngxlog("Can't get " .. key .. " from redis: ", err)
        return default_value
    else
        return res
    end
end

function redis_smembers(key)
    local res, err = red:smembers(key)
    if not res then
        ngxlog("Can't get " .. key .. " from redis: ", err)
    else
        return res
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
