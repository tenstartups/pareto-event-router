DOCKER_IMAGE_NAME := tenstartups/pareto-event-router:latest

build: Dockerfile
	docker build --file Dockerfile --tag $(DOCKER_IMAGE_NAME) .

clean_build: Dockerfile
	docker build --no-cache --pull --file Dockerfile --tag $(DOCKER_IMAGE_NAME) .

run: build
	docker run -it --rm \
	  -e FORMAT_LOGGING=false \
		-e PARETO_URL=https://pareto.reelyactive.com \
		-e PARETO_API_TOKEN=GET_ONE \
		-e MQTT_URL=mqtt://mqtt:mqtt@emqx:1883 \
		-e ELASTICSEARCH_URL=http://elasticsearch:9200 \
		-e ELASTICSEARCH_INDEX=pareto-rtls-events \
		-e ELASTICSEARCH_TYPE=pareto-rtls-event \
		--net development \
		--name pareto-event-router \
		$(DOCKER_IMAGE_NAME) $(ARGS)

push: build
	docker push $(DOCKER_IMAGE_NAME)
