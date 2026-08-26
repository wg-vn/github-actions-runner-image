FROM catthehacker/ubuntu:act-latest

RUN apt-get update && \
    apt-get install -y mysql-server && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
