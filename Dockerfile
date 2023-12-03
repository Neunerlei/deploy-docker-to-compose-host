FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install \
      openssh-client \
      zip \
    -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

RUN mkdir -p --mode=0755 /usr/share/keyrings \
    && curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null \
    && echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
    && apt-get update && sudo apt-get install cloudflared \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY deploy-docker-to-compose-host.sh /opt/deploy-docker-to-compose-host.sh
RUN chmod +x /opt/deploy-docker-to-compose-host.sh

COPY makeProdEnv.sh /opt/makeProdEnv.sh
RUN chmod +x /opt/makeProdEnv.sh

ENTRYPOINT ["/opt/deploy-docker-to-compose-host.sh"]
