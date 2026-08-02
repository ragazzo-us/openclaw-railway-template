FROM node:24-bookworm

# 1. Atualiza e instala dependências essenciais do sistema (mesclado com python3-venv e pip)
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gosu \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    tini \
    build-essential \
    zip \
    unzip \
  && rm -rf /var/lib/apt/lists/*

# 2. Configura o Ambiente Virtual Python (VENV) como principal
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# 3. Instala todas as bibliotecas Python de análise e trading de uma vez
RUN pip install --no-cache-dir \
    "pandas==2.3.3" \
    "numpy==2.2.6" \
    "scipy==1.18.0" \
    "openpyxl==3.1.5" \
    "pandas-ta==0.4.71b0" \
    "vectorbt==1.0.0" \
    "backtrader==1.9.78.123" \
    "statsmodels==0.14.6" \
    "scikit-learn==1.9.0" \
    "numba==0.61.2" \
    "PyMySQL<1.2.0" \
    "oandapyV20==0.7.2" \
    "yfinance==1.5.1" \
    "ccxt==4.5.68" \
    "matplotlib==3.11.1" \
    "seaborn==0.13.2" \
    "plotly==6.9.0" \
    "fpdf2==2.8.7" \
    "gspread==6.2.1" \
    "google-auth==2.56.2" \
    "google-auth-oauthlib==1.4.0" \
    "google-api-python-client==2.198.0" \
    "pytz"

# 4. Instalação padrão do OpenClaw
RUN npm install -g openclaw@2026.7.1-2
RUN npm install -g clawhub@latest

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod

COPY src ./src
COPY --chmod=755 entrypoint.sh ./entrypoint.sh

# 5. Configuração de permissões e usuários
RUN useradd -m -s /bin/bash openclaw \
  && chown -R openclaw:openclaw /app \
  && mkdir -p /data && chown openclaw:openclaw /data \
  && mkdir -p /home/linuxbrew/.linuxbrew && chown -R openclaw:openclaw /home/linuxbrew

USER openclaw
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 6. Configuração de variáveis de ambiente do Homebrew (mantendo o VENV do Python ativo)
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"

ENV PORT=8080
ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -f http://localhost:8080/setup/healthz || exit 1

USER root
ENTRYPOINT ["tini", "--", "./entrypoint.sh"]
