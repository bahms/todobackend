FROM bahms/todobackend-base
MAINTAINER Mamadou Saliou BAH

RUN 	apt-get update && \
	apt-get install -qy python-dev libmysqlclient-dev

RUN 	. appenv/bin/activate && \
	pip install wheel --upgrade

ENV WHEELHOUSE=/wheelhouse PIP_WHEEL_DIR=/wheelhouse PIP_FIND_LINKS=/wheelhouse XDG_CACHE_HOME=/cache

VOLUME /wheelhouse

VOLUME /reports

VOLUME /build

COPY scripts/test.sh /usr/local/bin/test.sh
RUN chmod +x /usr/local/bin/test.sh

ENTRYPOINT ["test.sh"]
CMD ["python", "manage.py", "test", "--noinput"]

COPY src /application
WORKDIR /application
