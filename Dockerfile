FROM nfcore/base
LABEL authors="Jorrit Boekel" \
      description="Docker image containing all requirements for nf-core/labelcheck pipeline"

COPY environment.yml /
COPY tools /tools/

RUN conda env create -f /environment.yml && conda clean -a
RUN conda env create -f /tools/openms/environment.yml && conda clean -a

ENV PATH /opt/conda/envs/nf-core-labelcheck-1.1/bin:$PATH
