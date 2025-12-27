# Use the Docker Hub mirror of the n8n runner image because docker.n8n.io
# does not host the 2.0.0 tag and the build fails with "not found".
FROM n8nio/runners:2.0.0

USER root

# Install Python packages into the runner virtualenv
RUN cd /opt/runners/task-runner-python && \
    uv pip install --python .venv/bin/python yt_dlp numpy pandas

# Apply custom runner configuration
COPY task-runners.json /etc/n8n-task-runners.json

USER runner
