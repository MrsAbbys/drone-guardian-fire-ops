FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /opt/game

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates libasound2 libatomic1 libfontconfig1 libfreetype6 libgcc-s1 \
		libpulse0 libstdc++6 libx11-6 libxcursor1 libxfixes3 libxi6 libxinerama1 \
		libxkbcommon0 libxrandr2 libxrender1 python3 \
	&& rm -rf /var/lib/apt/lists/* \
	&& useradd --system --uid 10001 --home-dir /nonexistent --shell /usr/sbin/nologin game \
	&& mkdir -p /var/log/drone-game \
	&& chown -R game:game /opt/game /var/log/drone-game

COPY exports/linux-server/drone-server.x86_64 /opt/game/drone-server.x86_64
COPY server/directorio/directorio.py /opt/game/server/directorio/directorio.py

RUN chmod 0755 /opt/game/drone-server.x86_64 \
	&& chown -R game:game /opt/game/server

USER game:game

EXPOSE 9000-9007/tcp
EXPOSE 9000-9007/udp

ENTRYPOINT ["/opt/game/drone-server.x86_64", "--headless", "--"]
CMD ["--server"]
