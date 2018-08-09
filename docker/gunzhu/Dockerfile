FROM docker.io/openresty/openresty:alpine
MAINTAINER your_name <your_email_address>
LABEL Description="This image is the base openresty images."  Version="1.0"
RUN mkdir -p /service/data
RUN mkdir -p /service/config
RUN mkdir -p /usr/local/openresty/nginx/logs
RUN mkdir -p /usr/local/openresty/nginx/lua/
COPY ./lua/guanzhu.lua /usr/local/openresty/nginx/lua/
COPY ./lua/guanzhu_timer.lua /usr/local/openresty/nginx/lua/
COPY ./nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY ./lua/http.lua /usr/local/openresty/lualib/resty/
COPY ./lua/http_headers.lua /usr/local/openresty/lualib/resty/
