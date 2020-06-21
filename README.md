# Batch SSH Password change
Change passwords for a specific user in a remote Server (Linux or AIX) using SSH in BASH

## Table of Contents
<!-- TOC -->

- [Batch SSH Password change](#batch-ssh-password-change)
    - [Table of Contents](#table-of-contents)
    - [Introduction](#introduction)
    - [Requirements](#requirements)
    - [Usage](#usage)
        - [Single](#single)
        - [Batch](#batch)
            - [Heading](#heading)
            - [Body](#body)
            - [Example](#example)
        - [Launch the script and feed it with the file](#launch-the-script-and-feed-it-with-the-file)
    - [Notes](#notes)
    - [Options](#options)

<!-- /TOC -->

## Introduction
In the project i am working on since last year u have to manage multiple personal users on over 200+ hosts accessible via ssh. 

This is pretty time-consuming and very boring, so i decided to try and build something that did that for me :wink:


## Requirements
The script will check if you fullfill all the requirements.
- **Bash** version >= **4.0**
- **Sshpass** (download for [Linux-Unix](https://www.cyberciti.biz/faq/noninteractive-shell-script-ssh-password-provider/) and [Windows](https://gist.github.com/arunoda/7790979#installing-from-the-source))

## Usage
### Single
Don't know why you would, but you can also use this script to change the password of a single server. 

To do that, simply start the script with the following **positional** parameters:
```bash
./password_change2.sh HOSTNAME_OR_IP USERNAME OLD_PASSWORD NEW_PASSWORD
```
### Batch
This is by the way the most useful feature of the script and the one i built it for...

To use it you'll need to **create a file** containing all the hostname/ip to ssh into and other data (optional) and **feed it to the script** by using the `-f` parameter followed by the filename

#### Heading
- The first line MUST be the **heading**, where you can specify the fields you want to use. They can be:
    -  *MACCHINA*: The **target server** (can be an hostname specified in your hosts file, an IP or a hostname reachable through a dns)
    -  *UTENZA*: The **username** you want to  change the password [optional]
    -  *PASSWORD*: The **old passowrd** [optional]
    -  *NUOVA_PASWORD*: The **new password** [optional]

- You can separate the fields using <kbd>;</kbd>, <kbd>,</kbd> or <kbd>TAB</kbd> character. The separator used for the heading is going to determine the one used for ALL the other lines

#### Body 
- The lines of the body (the ones containing the *actual* data) **MUST** follow the same **field order** and **MUST** not be **blank** or ignore a field, otherwise they will be ***skipped***

- To **comment** out a line you can put at the start of the line the **<kbd>#</kbd>** character (*as if you were in a bash/python script*)


#### Example
Creating the file `my_list.txt` with the following
content:
```
MACCHINA;UTENZA;PASSWORD;NUOVA_PASWORD
10.11.12.13;my_username;my_password;my_new_password

# This line will be skipped
172.16.1.5;spiderman;ugly_pw;beautiful_pw
```

### Launch the script and feed it with the file
```bash
./password_change2.sh -f my_list.txt
```

## Notes
- If the **username is the same** for all the hosts you want to login into, you can **omit** it from the heading and the data. The script will automatically **ask** ONCE for it and use it throughout the process. The same goes for the new/old password.

- The help embedded in the script and the headings as of 06/2020 are ONLY in Italian. I'm planning to convert them in English language

## Options
- `-f`: Specify the file to be used for Batch operations (see the [Batch section](#batch))
- `-c`: If used in BATCH_MODE, don't change passwords. Just check the expiral date (`chage -l`-like output) of every entry
- `-P`: Enable the PICO rule (**only for** the **PICO Trenitalia** project i work at):
    - Uppercase all AIX username (hostname ending with `x`) 
    - Lowercase the Linux ones (hostname ending with `r`). 
- `-h`: Print the help and exit the script