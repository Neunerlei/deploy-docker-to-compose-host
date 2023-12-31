FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install \
      openssh-client \
      curl \
      zip \
    -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

RUN mkdir -p --mode=0755 /usr/share/keyrings \
    && curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null \
    && echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | tee /etc/apt/sources.list.d/cloudflared.list \
    && apt-get update && apt-get install cloudflared -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY /opt/deploy-docker-to-compose-host.sh /opt/deploy-docker-to-compose-host.sh
RUN chmod +x /opt/deploy-docker-to-compose-host.sh

COPY /opt/makeProdEnv.sh /opt/makeProdEnv.sh
RUN chmod +x /opt/makeProdEnv.sh

RUN mkdir -p /work \
    chmod 777 /work

WORKDIR /work
ENTRYPOINT ["/opt/deploy-docker-to-compose-host.sh"]
