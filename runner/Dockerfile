FROM ubuntu-debootstrap:14.04

ENV DEBIAN_FRONTEND noninteractive

# install common packages
RUN apt-get update && apt-get install -y python-dev curl git net-tools

# install etcdctl
RUN curl -sSL -o /usr/local/bin/etcdctl https://s3-us-west-2.amazonaws.com/opdemand/etcdctl-v0.4.6 \
    && chmod +x /usr/local/bin/etcdctl

# install pip
RUN curl -sSL https://raw.githubusercontent.com/pypa/pip/1.5.6/contrib/get-pip.py | python -

# install deis s3cmd
RUN pip install git+https://github.com/deis/s3cmd
RUN pip install python-dateutil

# Clean up APT and temporary files
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy backup script
COPY backup.sh /home/backup.sh
RUN  chmod +x /home/backup.sh

# Define default command.
CMD ["bash"]