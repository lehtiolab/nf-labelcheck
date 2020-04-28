FROM nfcore/base:1.9
LABEL authors="Jorrit Boekel" \
      description="Docker image containing all requirements for nf-core/labelcheck pipeline"

COPY environment.yml /
RUN conda env create -f /environment.yml && conda clean -a

ENV PATH /opt/conda/envs/nf-core-labelcheck-1.2/bin:$PATH
