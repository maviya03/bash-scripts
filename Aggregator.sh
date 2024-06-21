#!/bin/bash

# Configuration
username="your_username"
email="recipient@example.com"
subject="Aggregator ID Mismatch Report"
server_list="server.txt"
report_file="/tmp/aggregator_report.txt"
command="cat /proc/net/bonding/bond0 | grep -A8 ens | egrep 'Slave Interface:|Aggregator ID:'"

# Initialize the report file
echo "Aggregator ID Mismatch Report" > "$report_file"
echo "=============================" >> "$report_file"

# Function to check aggregator IDs on a server
check_aggregator_ids() {
    local server="$1"
    echo "Checking $server..."

    # Execute the command on the remote server and capture output
    output=$(ssh -n -o ConnectTimeout=10 -o BatchMode=yes "$username@$server" "$command" 2>&1)
    ssh_exit_status=$?

    if [ $ssh_exit_status -ne 0 ]; then
        echo "$server: SSH connection failed or command error: $output" >> "$report_file"
        return 1
    fi

    # Parse the output to find aggregator IDs
    interfaces=()
    aggregator_ids=()
    while IFS= read -r line; do
        if [[ $line == "Slave Interface:"* ]]; then
            interface=$(echo "$line" | awk '{print $3}')
            interfaces+=("$interface")
        elif [[ $line == "Aggregator ID:"* ]]; then
            aggregator_id=$(echo "$line" | awk '{print $3}')
            aggregator_ids+=("$aggregator_id")
        fi
    done <<< "$output"

    # Check if all aggregator IDs are the same
    unique_aggregator_ids=($(printf "%s\n" "${aggregator_ids[@]}" | sort -u))
    if [ ${#unique_aggregator_ids[@]} -ne 1 ]; then
        echo "$server: Aggregator ID mismatch found" >> "$report_file"
        for (( i=0; i<${#interfaces[@]}; i++ )); do
            echo "  ${interfaces[$i]}: ${aggregator_ids[$i]}" >> "$report_file"
        done
        return 1
    fi

    return 0
}

# Loop through each server in server_list
while IFS= read -r server || [ -n "$server" ]; do
    if [ -n "$server" ]; then  # Check if the line read is not empty
        check_aggregator_ids "$server"
    fi
done < "$server_list"

# Send the report if any discrepancies were found
if grep -q "Aggregator ID mismatch found" "$report_file"; then
    mutt -s "$subject" "$email" < "$report_file"
    echo "Report sent to $email."
else
    echo "No discrepancies found."
fi

# Clean up the report file
rm -f "$report_file"

