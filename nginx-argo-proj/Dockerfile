# Use the official NGINX image
FROM nginx:latest

# Copy the custom NGINX config
COPY ./nginx.conf /etc/nginx/conf.d/default.conf

# Copy the custom HTML file to the default NGINX web directory
COPY ./index.html /usr/share/nginx/html/index.html

# Expose port 80 for HTTP traffic
EXPOSE 80
