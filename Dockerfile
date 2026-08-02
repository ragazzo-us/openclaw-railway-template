# Debian 13 (trixie) => Python 3.13.
# CRITICO: node:24-bookworm traz Python 3.11, e scipy==1.18.0 / pandas-ta==0.4.71b0
# exigem >=3.12. Nao volte para bookworm sem trocar esses dois pins.
# Nao suba para uma base com Python 3.14: numba==0.61.2 e numpy==2.2.6 nao tem wheel cp314.
FROM node:24-trixie

# 1. Dependencias de sistema
#    'sudo' e necessario para o instalador do Homebrew (etapa 5): mesmo com
#    NONINTERACTIVE=1 ele chama have_sudo_access() -> /usr/bin/sudo -v
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gosu \
    sudo \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    tini \
    build-essential \
    zip \
    unzip \
  && rm -rf /var/lib/apt/lists/*

# 2. Virtualenv Python
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Falha cedo e com mensagem clara se a base nao tiver Python >=3.12
RUN python -c "import sys; assert sys.version_info >= (3,12), f'Python {sys.version} e antigo demais para scipy 1.18 / pandas-ta 0.4.x'" \
  && python -V \
  && pip install --no-cache-dir --upgrade pip

# 3. Bibliotecas Python, em camadas separadas.
#    Um pin quebrado agora derruba so a sua camada, e as anteriores ficam em cache.

# 3a. Base numerica (a mais pesada; muda pouco)
RUN pip install --no-cache-dir \
    "numpy==2.2.6" \
    "pandas==2.3.3" \
    "scipy==1.18.0" \
    "numba==0.61.2" \
    "statsmodels==0.14.6" \
    "scikit-learn==1.9.0" \
    "pytz"

# 3b. Analise tecnica e backtesting
RUN pip install --no-cache-dir \
    "pandas-ta==0.4.71b0" \
    "vectorbt==1.0.0" \
    "backtrader==1.9.78.123"

# 3c. Conectores de mercado e banco
RUN pip install --no-cache-dir \
    "ccxt==4.5.68" \
    "yfinance==1.5.1" \
    "oandapyV20==0.7.2" \
    "PyMySQL<1.2.0"

# 3d. Graficos, planilhas e relatorios
RUN pip install --no-cache-dir \
    "matplotlib==3.11.1" \
    "seaborn==0.13.2" \
    "plotly==6.9.0" \
    "openpyxl==3.1.5" \
    "fpdf2==2.8.7"

# 3e. Google APIs
RUN pip install --no-cache-dir \
    "gspread==6.2.1" \
    "google-auth==2.56.2" \
    "google-auth-oauthlib==1.4.0" \
    "google-api-python-client==2.198.0"

# Trava o resultado: falha o build agora, e nao em runtime
RUN pip check && python -c "import pandas, numpy, scipy, pandas_ta, vectorbt, sklearn, numba; print('python stack OK')"

# 4. OpenClaw
RUN npm install -g openclaw@2026.7.1-2 clawhub@latest

WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod
COPY src ./src
COPY --chmod=755 entrypoint.sh ./entrypoint.sh

# 5. Usuario e permissoes
RUN useradd -m -s /bin/bash openclaw \
  && chown -R openclaw:openclaw /app \
  && mkdir -p /data && chown openclaw:openclaw /data \
  && mkdir -p /home/linuxbrew/.linuxbrew && chown -R openclaw:openclaw /home/linuxbrew \
  && echo 'openclaw ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/openclaw \
  && chmod 0440 /etc/sudoers.d/openclaw

USER openclaw
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 6. Ambiente
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
