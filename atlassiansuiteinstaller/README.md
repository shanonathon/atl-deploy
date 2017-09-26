# README #

Welcome to the Atlassian Suite Installer and Runner!

### What is this repository for? ###

* Use this tool to install and run Atlassian applications.
* Version 1.0

### How do I get set up? ###

Summary of set up

1. Clone this repository in order to download the atl.sh file.

2. Fix file permissions if needed.

3. All application binaries will be placed at $HOME/atlassian/apps/<app_name>/<app_version>

4. All application data will be placed at $HOME/atlassian/data/<app_name>/<app_version>
  
Configuration

* So as to be able to run the tool from anywhere in Terminal, I recommend adding an alias to this tool in your .bash_profile.

* For example: 
alias atl="/Users/fkraemer/atlassian/scripts/atl.sh"

Dependencies

* This tool relies on wget for downloading packages. Make sure that wget is installed.
* If you wish to connect the application to an external database during the application setup wizard in the web interface, this tool is ready for MySQL and PostgreSQL database types, so make sure to have MySQL and / or PostgreSQL installed. The tool will download the JDBC driver (if needed), create the database schema and user for you!

Usage:

- Parameter 1: Application Name (fecru | bitbucket | bamboo | jira-software | jira-core | jira-servicedesk | crowd | confluence)
- Parameter 2: Application Version
- Parameter 3: Execution type (install | start | stop | restart)
- Parameter 4: Database Type (mysql | postgresql). To use the built-in database, do not specify this parameter.

- Example   1: atl fecru 4.4.1 install mysql
- Example   2: atl jira-core 7.4.0 install postgres
- Example   3: atl bitbucket 5.1.0 start
- Example   4: atl bamboo 6.1.0 restart
- Example   5: atl jira-software 7.4.0 stop


### Who do I talk to? ###

* Felipe Kraemer (fkraemer@atlassian.com / felipekraemer@gmail.com)