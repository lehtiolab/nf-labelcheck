FROM nfcore/base
LABEL authors="Jorrit Boekel" \
      description="Docker image containing all requirements for lehtiolab nf-core/labelcheck pipeline"

COPY environment.yml /

RUN conda env create -f /environment.yml && conda clean -a

ENV PATH /opt/conda/envs/nf-core-labelcheck-2.1/bin:$PATH
