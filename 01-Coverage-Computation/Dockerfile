ARG TWO_STAGE_ARTIFACT_DOCKER_IMAGE_NAME
FROM ${TWO_STAGE_ARTIFACT_DOCKER_IMAGE_NAME}

# Copy source in case we need it to resolve, e.g., dwarf references.
RUN  tar xzf /benchmark/source/cflow-1.6.tar.gz -C /benchmark
RUN  tar xzf /benchmark/source/binutils-2.30.tar.gz -C /benchmark
RUN  tar xzf /benchmark/source/mujs-1.0.2.tar.gz -C /benchmark
RUN  tar xzf /benchmark/source/mupdf-1.12.0-source.tar.gz -C /benchmark
RUN  tar xzf /benchmark/source/ncurses-6.2.tar.gz -C /benchmark
RUN  cp -r /benchmark/source/libdwarf-20190529 /benchmark/
RUN  cp -r /benchmark/source/w3m-v0.5.3+git20220429 /benchmark/

COPY requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt
RUN apt install chromium-chromedriver firefox -y