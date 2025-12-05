FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y wget curl && rm -rf /var/lib/apt/lists/*

# --------------------------------------------------------
# THE FIX: Use Miniforge instead of Miniconda
# --------------------------------------------------------
# Miniforge defaults to conda-forge and has NO Terms of Service check.
ENV CONDA_DIR=/opt/conda
RUN wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O /tmp/miniforge.sh \
    && bash /tmp/miniforge.sh -b -p $CONDA_DIR \
    && rm /tmp/miniforge.sh

ENV PATH=$CONDA_DIR/bin:$PATH

# Initialize bash (optional, but good practice)
RUN conda init bash

# --------------------------------------------------------
# TEST
# --------------------------------------------------------
# This will work immediately because "defaults" (Anaconda channel) 
# is not even in the configuration list.
RUN conda create -n test-env python=3.8 -y

CMD ["echo", "Miniforge (Conda) is working perfectly!"]