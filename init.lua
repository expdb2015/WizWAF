-- LOG

cjson = require "cjson"
function debuglog(...)
    local log_table = {}
    for i = 1, select("#", ...) do
        log_table[i] = select(i, ...)
    end
    ngx.log(ngx.ERR, "[WIZWAF-DEBUG] ", cjson.encode(log_table))
end

function ngxlog(...)
    ngx.log(ngx.ERR, "[WIZWAF] ", ...)
end

fd_log, err = io.open("/var/log/waf/waf.log","ab")
if not fd_log then
    ngxlog(err)
end

function log_file(item)
    fd_log:write(item)
    fd_log:flush()
end

-- LOG END

-- UTILS

function split(str, sep)
    local fields = {}
    str:gsub("[^"..sep.."]+", function(c) fields[#fields+1] = c end)
    return fields
end

function wizwaf_output()
    ngx.status = ngx.HTTP_FORBIDDEN
    ngx.header.content_type = 'text/html'
    ngx.say([[
<!DOCTYPE html>
<html lang="zh-CN">
<head>
        <meta charset="utf-8">
</head>
<body style="width:100%;height:100%;background:#0066cc;">
        <h1 style="color:#FFF;text-align:center;">You have been blocked by WIZWAF.</h1>
</body>
</html>
]])
    ngx.exit(ngx.HTTP_FORBIDDEN)
end

-- UTILS END

-- REDIS

local redis = require "resty.redis_iresty"
red = redis:new()
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

-- REDIS END

-- RABBITMQ

local rabbitmq = require "resty.rabbitmqstomp"
function log_rabbitmq(log_json)
    local RABBITMQ_HOST = "127.0.0.1"
    local RABBITMQ_PORT = 61613

    local RABBITMQ_USERNAME = "guest"
    local RABBITMQ_PASSWORD = "guest"
    local RABBITMQ_VHOST = "/"

    local EXCHANGE_NAME = "wizwaf"
    local QUEUE_NAME = "log"

    local RABBITMQ_OPT_PERSISTENT = "true"

    local opts = {
        username = RABBITMQ_USERNAME,
        password = RABBITMQ_PASSWORD,
        vhost = RABBITMQ_VHOST
    }
    local mq, err = rabbitmq:new(opts)
    if not mq then
        ngxlog("Can't new rabbitmq: " .. err)
        return
    end
    mq:set_timeout(2000)

    local ok, err = mq:connect(RABBITMQ_HOST, RABBITMQ_PORT)
    if not ok then
        ngxlog("Can't connect to rabbitmq: " .. err)
        return
    end

    local headers = {}
    headers["destination"] = "/exchange/" .. EXCHANGE_NAME .. "/" .. QUEUE_NAME
    headers["persistent"] = RABBITMQ_OPT_PERSISTENT
    headers["content-type"] = "application/json"

    local ok, err = mq:send(log_json, headers)
    if not ok then
        ngxlog("Can't send log to rabbitmq: " .. err)
        return
    else
        --ngxlog("Log have been sent to rabbitmq: " .. log_json)
    end

    local ok, err = mq:set_keepalive(30000, 30000)
    if not ok then
        ngxlog("Can't set rabbitmq keepalive: " .. err)
    else
        --ngxlog("Set rabbitmq keepalive: 30s")
    end
end

-- RABBITMQ END
