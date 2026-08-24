FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    libfontconfig1 \
    libasound2 \
    libpulse0 \
    libxcursor1 \
    libxinerama1 \
    libxrandr2 \
    libgl1 \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -o /tmp/godot.zip \
    && unzip /tmp/godot.zip -d /usr/local/bin \
    && mv "/usr/local/bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

# Define o diretório de trabalho do projeto
WORKDIR /app

# Copia todos os arquivos do projeto para o container
COPY . .

# Indexa as classes globais (PlayerData, PlayerSpriteFrames etc.) na imagem.
# O servidor headless usa esse cache ao carregar as cenas multiplayer.
RUN godot --headless --path . --editor --quit

# O Render injeta PORT; o NetworkManager o utiliza quando presente.
EXPOSE 10000

CMD ["godot", "--headless", "--path", "."]
