FROM python:3.11-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Install system dependencies for build, Postgres and GDAL/PostGIS
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    binutils \
    libproj-dev \
    gdal-bin \
    libgdal-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /code

# Install python dependencies
COPY requirements.txt /code/
RUN pip install --no-cache-dir -r requirements.txt

# Copy project files
COPY . /code/

EXPOSE 8000
