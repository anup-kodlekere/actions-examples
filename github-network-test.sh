#!/bin/bash

# Base directory to save logs, with a timestamp appended
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_BASE_DIR="/tmp/github-logs/$TIMESTAMP"
mkdir -p "$LOG_BASE_DIR"

# File to track success/failure of each command
STATUS_LOG="$LOG_BASE_DIR/command_status.log"

# Function to log output with timestamps
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$STATUS_LOG"
}

# Function to install required packages for CentOS/RHEL
install_centos_packages() {
    sudo yum install -y curl bind-utils traceroute iproute iputils iptables tcpdump openssl
}

# Function to install required packages for Ubuntu/Debian
install_ubuntu_packages() {
    sudo apt-get update
    sudo apt-get install -y curl dnsutils traceroute iproute2 iputils-ping iptables tcpdump openssl
}

# Function to extract the domain from a URL
extract_domain() {
    echo "$1" | sed -E 's#^https?://##' | sed 's#/.*##'
}

# Ensure the log directory exists
mkdir -p "$LOG_BASE_DIR"
log "Log directory created at $LOG_BASE_DIR"

# Detect OS and install missing tools
OS_TYPE=$(cat /etc/*release | grep -i '^ID=' | cut -d'=' -f2)

if [[ "$OS_TYPE" == "centos" || "$OS_TYPE" == "rhel" ]]; then
    log "Detected CentOS or RHEL. Checking for required tools..."
    # Install required packages for CentOS/RHEL if not installed
    if ! command -v curl &> /dev/null; then install_centos_packages; fi
    if ! command -v nslookup &> /dev/null; then install_centos_packages; fi
    if ! command -v traceroute &> /dev/null; then install_centos_packages; fi
    if ! command -v ping &> /dev/null; then install_centos_packages; fi
    if ! command -v iptables &> /dev/null; then install_centos_packages; fi
    if ! command -v tcpdump &> /dev/null; then install_centos_packages; fi
    if ! command -v openssl &> /dev/null; then install_centos_packages; fi
elif [[ "$OS_TYPE" == "ubuntu" || "$OS_TYPE" == "debian" ]]; then
    log "Detected Ubuntu or Debian. Checking for required tools..."
    # Install required packages for Ubuntu/Debian if not installed
    if ! command -v curl &> /dev/null; then install_ubuntu_packages; fi
    if ! command -v nslookup &> /dev/null; then install_ubuntu_packages; fi
    if ! command -v traceroute &> /dev/null; then install_ubuntu_packages; fi
    if ! command -v ping &> /dev/null; then install_ubuntu_packages; fi
    if ! command -v iptables &> /dev/null; then install_ubuntu_packages; fi
    if ! command -v tcpdump &> /dev/null; then install_ubuntu_packages; fi
    if ! command -v openssl &> /dev/null; then install_ubuntu_packages; fi
else
    log "Unsupported OS: $OS_TYPE. Please install the required tools manually."
    exit 1
fi

# Start logging
log "Starting GitHub connectivity and network debugging test..."

# Record start time
START_TIME=$(date +%s)

# 1. Loop through each URL and run tests
urls=( 
    "https://api.github.com/"
    "https://vstoken.actions.githubusercontent.com/_apis/health"
    "https://pipelines.actions.githubusercontent.com/_apis/health"
    "https://results-receiver.actions.githubusercontent.com/health"
)

# 1. Test each URL for connectivity and network diagnostics
for url in "${urls[@]}"; do
    url_name=$(echo "$url" | sed 's/[^a-zA-Z0-9]/_/g')  # Sanitize URL to be a valid filename
    log "Testing connectivity for $url..."

    # Extract the domain for use in the tests
    domain=$(extract_domain "$url")

    # Start tcpdump in the background, capturing traffic for the extracted domain
    log "Capturing network traffic for $domain..."
    sudo tcpdump -i eth0 host "$domain" -c 10 -w "$LOG_BASE_DIR/tcpdump_capture_$url_name.pcap" &

    # Test the URL connectivity with curl (verbose)
    log "Running curl for $url (verbose)..."
    curl -v "$url" &> "$LOG_BASE_DIR/curl_test_$url_name.log"
    if [[ $? -eq 0 ]]; then
        log "Connectivity test for $url succeeded."
    else
        log "Connectivity test for $url failed."
    fi

    # Test DNS resolution for the URL (verbose)
    log "Testing DNS resolution for $url..."
    nslookup "$domain" &> "$LOG_BASE_DIR/dns_resolution_$url_name.log"
    if [[ $? -eq 0 ]]; then
        log "DNS resolution test for $url succeeded."
    else
        log "DNS resolution test for $url failed."
    fi

    # Run traceroute for the domain (verbose)
    log "Running traceroute for $domain..."
    traceroute "$domain" &> "$LOG_BASE_DIR/traceroute_$url_name.log"
    if [[ $? -eq 0 ]]; then
        log "Traceroute test for $url succeeded."
    else
        log "Traceroute test for $url failed."
    fi

    # Stop tcpdump after the tests
    pkill -f "tcpdump.*$domain"
done

# 4. Archive the logs after testing completes, including tcpdump capture files
log "Archiving logs and tcpdump captures..."
tar -czf "$LOG_BASE_DIR.tar.gz" -C "$LOG_BASE_DIR" .

# End of Script: Final message
END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME - START_TIME))
log "GitHub connectivity and network debugging test completed in $EXECUTION_TIME seconds."
