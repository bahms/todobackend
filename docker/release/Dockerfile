FROM bahms/todobackend-base:latest
MAINTAINER Mamadou Saliou BAH

COPY target /wheelhouse

RUN 	. /appenv/bin/activate && \
	pip install --no-index -f /wheelhouse todobackend && \
	rm -rf /wheelhouse

