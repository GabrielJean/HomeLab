FROM mcr.microsoft.com/azure-cli:2.91.0

# Copy the script into the container
COPY update_dns.sh /usr/local/bin/update_dns.sh

# Make the script executable
RUN chmod +x /usr/local/bin/update_dns.sh

# Set the script as the container's command
CMD ["/usr/local/bin/update_dns.sh"]
