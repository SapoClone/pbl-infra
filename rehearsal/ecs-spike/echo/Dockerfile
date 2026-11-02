# Stands in for a service image: answers /health, and /cgi-bin/env and /cgi-bin/peer for spike.sh test.
FROM busybox:1.36.1
COPY www /www
RUN chmod +x /www/cgi-bin/*
CMD ["sh", "-c", "exec httpd -f -v -p \"${PORT:-3000}\" -h /www"]
