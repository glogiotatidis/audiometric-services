FROM ubuntu-debootstrap:14.04

ENV DEBIAN_FRONTEND noninteractive

# install common packages
RUN apt-get update && apt-get install -y python-dev

# install pip
RUN curl -sSL https://raw.githubusercontent.com/pypa/pip/1.5.6/contrib/get-pip.py | python -

# install deis s3cmd
RUN pip install git+https://github.com/deis/s3cmd

# Define default command.
CMD ["bash"]