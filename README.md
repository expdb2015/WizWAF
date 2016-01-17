# WizWAF

基于openresty/lua-nginx-module的全新设计的WAF系统

A new WAF based on openresty/lua-nginx-module

### Dependencies:

- openresty or nginx with openresty/lua-nginx-module
- openresty-best-practices/redis_iresty.lua
- wingify/lua-resty-rabbitmqstomp


### Installation:

将代码放在位于nginx根目录下的lua/wizwaf/下

Put the code into the directory lua/wizwaf/ which is located in the root directory of the nginx

在nginx.conf的http段中添加如下配置：

Add the config below to the http seg in nginx.conf:

>    lua_package_path "/usr/local/openresty/nginx/lua/WizWAF/?.lua;;";

>    init_by_lua_file lua/WizWAF/init.lua;

>    access_by_lua_file lua/WizWAF/waf.lua;

>    lua_shared_dict redis_cache 10m;
