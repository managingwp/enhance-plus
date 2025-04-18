# enhance-log-capture
The goal of this repository is to capture and maintain the web server log files on the enhance platform.
* Utilizes systemd and a bash script with inotifywait
* Always looking for feedback and improvement

# Caveats
* Some logs entries might be missed due to the log file being rotated.
* The log entries might be out of order.

# Install
This is an example install. You will want to be logged in as root.
1. `mkdir -p $HOME/bin;cd $HOME/bin`
2. `git clone https://github.com/managingwp/enhance-log-capture.git`
3. `cd enhance-log-capture`
4. `./install.sh`
