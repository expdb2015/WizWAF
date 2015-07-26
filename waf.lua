local localtime = ngx.localtime()

local request_method = ngx.var.request_method
local request_uri = ngx.unescape_uri(ngx.var.request_uri)
local server_protocol = ngx.var.server_protocol

local headers = ngx.req.get_headers()
local remote_addr = headers["X-Real-IP"] or ngx.var.remote_addr
local http_user_agent = ngx.var.http_user_agent
local http_referer = ngx.var.http_referer
local http_cookie = ngx.var.http_cookie

function log_file(module_name, why)
    local http_user_agent = http_user_agent or "-"
    local http_referer = http_referer or "-"
    local line = string.format([[[%s] "%s" : %s [%s] "%s %s %s" "%s" "%s"]] .. "\n", module_name, why, remote_addr, localtime, request_method, request_uri, server_protocol, http_referer, http_user_agent)
    fd_log:write(line)
    fd_log:flush()
end

function log(module_name, why)
    log_file(module_name, why)
end

function block_ip_module(mode)
    if red:sismember("DSWAF_BLOCK_IPS", remote_addr) == 1 then
        log("BLOCK_IP_MODULE", remote_addr)
        if mode == "ENABLE" then dswaf_output() end
    end
end

function block_url_module(mode)
    local block_url_slices = redis_smembers("DSWAF_BLOCK_URL_SLICES")
    if block_url_slices then
        for _, block_url_slice in ipairs(block_url_slices) do
            if ngx.re.match(request_uri, block_url_slice, "sjo") then
                log("BLOCK_URL_MODULE", block_url_slice)
                if mode == "ENABLE" then dswaf_output() end
            end
        end
    end
end

function block_user_agent_module(mode)
    local block_user_agent_slices = redis_smembers("DSWAF_BLOCK_UA_SLICES")
    if block_user_agent_slices then
        if http_user_agent then
            for _, block_user_agent_slice in ipairs(block_user_agent_slices) do
                if ngx.re.match(http_user_agent, block_user_agent_slice, "isjo") then
                    log("BLOCK_USER_AGENT_MODULE", block_user_agenti_slice)
                    if mode == "ENABLE" then dswaf_output() end
                end
            end
        end
    end
end

function block_cookie_module(mode)
    local block_cookie_slices = redis_smembers("DSWAF_BLOCK_COOKIE_SLICES")
    if block_cookie_slices then
        if http_cookie then
            for _, block_cookie_slice in ipairs(block_cookie_slices) do
                if ngx.re.match(http_cookie, block_cookie_slice, "sjo") then
                    log("BLOCK_COOKIE_MODULE", block_cookie_slice)
                    if mode == "ENABLE" then dswaf_output() end
                end
            end
        end
    end
end

function dymanic_block_ip_module(mode)
    local access_num = redis_get(remote_addr)
    if not access_num then
        red:incr(remote_addr)
        red:expire(remote_addr, 60)
    else
        red:incr(remote_addr)
        if tonumber(access_num) > tonumber(redis_get("DSWAF_DYMANIC_BLOCK_IPS_RATE", 10)) then
            log("DYMANIC_BLOCK_IP_MODULE", remote_addr .. "(" .. access_num .. ")")
            if mode == "ENABLE" then dswaf_output() end
        end
    end
end

local mode = redis_get("DSWAF_MODE", "ENABLE")
if mode == "ENABLE" or mode == "AUDIT" then
    block_ip_module(mode)
    block_url_module(mode)
    block_user_agent_module(mode)
    block_cookie_module(mode)
    dymanic_block_ip_module(mode)
else
end
