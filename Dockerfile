FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    git \
    curl \
    vim \
    sudo \
    build-essential \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Clone the repo
RUN git clone https://github.com/sameeeeeeep/autoclawd.git /workspace/autoclawd

WORKDIR /workspace/autoclawd

CMD ["bash"]
