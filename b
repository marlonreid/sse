["CMD-SHELL",
             "nc -z 127.0.0.1 5300 && \
              printf 'GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n' | \
                nc 127.0.0.1 5300 | grep -q '200 OK'"]
