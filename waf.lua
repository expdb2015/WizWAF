local localtime = ngx.localtime()

local request_method = ngx.var.request_method
local request_uri = ngx.unescape_uri(ngx.var.request_uri)
local server_protocol = ngx.var.server_protocol

local headers = ngx.req.get_headers()
local remote_addr = headers["X-Real-IP"] or ngx.var.remote_addr
local http_user_agent = ngx.var.http_user_agent
local http_referer = ngx.var.http_referer
local http_cookie = ngx.var.http_cookie


function log_file(item)
    fd_log:write(item)
    fd_log:flush()
end


function log_rabbitmq(log_json)
    local RABBITMQ_HOST = "127.0.0.1"
    local RABBITMQ_PORT = 61613

    local RABBITMQ_USERNAME = "guest"
    local RABBITMQ_PASSWORD = "guest"
    local RABBITMQ_VHOST = "/"

    local EXCHANGE_NAME = "test"
    local QUEUE_NAME = "binding"

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



function log(module_name, why)
    local log_table = {
        module_name = module_name,
        why = why,
        remote_addr = remote_addr,
        localtime = localtime,
        request_method = request_method,
        request_uri = request_uri,
        server_protocol = server_protocol,
        http_referer = http_referer,
        http_user_agent = http_user_agent
    }
    local log_json = cjson.encode(log_table)

    log_rabbitmq(log_json)
    --log_file(log_json .. "\n")

    local http_user_agent = http_user_agent or "-"
    local http_referer = http_referer or "-"
    local log_text = string.format([[[%s] "%s" : %s [%s] "%s %s %s" "%s" "%s"]], module_name, why, remote_addr, localtime, request_method, request_uri, server_protocol, http_referer, http_user_agent)

    log_file(log_text .. "\n")
end

function block_ip_module(mode)
    local block_ips = get_smembers_from_cache_or_redis("DSWAF_BLOCK_IPS")
    if block_ips then
        for _, block_ip in ipairs(block_ips) do
            if remote_addr == block_ip then
                log("BLOCK_IP_MODULE", remote_addr)
                if mode == "ENABLE" then dswaf_output() else return end
            end
        end
    end
end


function block_url_module(mode)
    local block_url_slices = get_smembers_from_cache_or_redis("DSWAF_BLOCK_URL_SLICES")
    if block_url_slices then
        for _, block_url_slice in ipairs(block_url_slices) do
            if ngx.re.match(request_uri, block_url_slice, "sjo") then
                log("BLOCK_URL_MODULE", block_url_slice)
                if mode == "ENABLE" then dswaf_output() else return end
            end
        end
    end
end


function block_user_agent_module(mode)
    local block_user_agent_slices = get_smembers_from_cache_or_redis("DSWAF_BLOCK_UA_SLICES")
    if block_user_agent_slices then
        if http_user_agent then
            for _, block_user_agent_slice in ipairs(block_user_agent_slices) do
                if ngx.re.match(http_user_agent, block_user_agent_slice, "isjo") then
                    log("BLOCK_USER_AGENT_MODULE", block_user_agenti_slice)
                    if mode == "ENABLE" then dswaf_output() else return end
                end
            end
        end
    end
end


function block_cookie_module(mode)
    local block_cookie_slices = get_smembers_from_cache_or_redis("DSWAF_BLOCK_COOKIE_SLICES")
    if block_cookie_slices then
        if http_cookie then
            for _, block_cookie_slice in ipairs(block_cookie_slices) do
                if ngx.re.match(http_cookie, block_cookie_slice, "sjo") then
                    log("BLOCK_COOKIE_MODULE", block_cookie_slice)
                    if mode == "ENABLE" then dswaf_output() else return end
                end
            end
        end
    end
end


function block_body_module(mode)
    local block_body_slices = get_smembers_from_cache_or_redis("DSWAF_BLOCK_BODY_SLICES")
    if block_body_slices then
        ngx.req.read_body()
        local post_args = ngx.req.get_post_args()
        for post_arg_key, post_arg_value in pairs(post_args) do
            for _, block_body_slice in ipairs(block_body_slices) do
                if ngx.re.match(post_arg_value, block_body_slice, "sjo") then
                    log("BLOCK_COOKIE_MODULE", post_arg_key .. ":" .. post_arg_value .. "(" .. block_body_slice .. ")")
                    if mode == "ENABLE" then dswaf_output() else return end
                end
            end
        end
    end
end


function dymanic_block_ip_module_redis(mode)
    local access_num = red:get(remote_addr)
    if not access_num then
        red:incr(remote_addr)
        red:expire(remote_addr, 60)
    else
        red:incr(remote_addr)
        if tonumber(access_num) > tonumber(get_value_from_cache_or_redis("DSWAF_DYMANIC_BLOCK_IPS_RATE") or 1000) then
            log("DYMANIC_BLOCK_IP_MODULE", remote_addr .. "(" .. access_num .. ")")
            if mode == "ENABLE" then dswaf_output() else return end
        end
    end
end


function dymanic_block_ip_module_cache(mode)
    ngx.shared.redis_cache:safe_add(remote_addr, 1, 60)
    ngx.shared.redis_cache:incr(remote_addr, 1)
    local access_num, err = ngx.shared.redis_cache:get(remote_addr)
    if access_num and access_num > tonumber(get_value_from_cache_or_redis("DSWAF_DYMANIC_BLOCK_IPS_RATE") or 1000) then
        log("DYMANIC_BLOCK_IP_MODULE", remote_addr .. "(" .. access_num .. ")")
        if mode == "ENABLE" then dswaf_output() else return end
    end
end


local mode = get_value_from_cache_or_redis("DSWAF_MODE") or "ENABLE"
if mode == "ENABLE" or mode == "AUDIT" then
    block_ip_module(mode)
    block_url_module(mode)
    block_user_agent_module(mode)
    block_cookie_module(mode)
    --dymanic_block_ip_module_redis(mode)
    dymanic_block_ip_module_cache(mode)
    if request_method == "POST" and headers["Content-Type"] == "application/x-www-form-urlencoded" then block_body_module(mode) end 
else
end


