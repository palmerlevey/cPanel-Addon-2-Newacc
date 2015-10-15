#!/bin/sh
# cPanel Addon Domain >> New Account Tool
# https://git.privatesystems.net/dlevey/cp-addon-to-newacc

##
## Variables
##

version="early.alpha.1";

# Tool path variables
cp_a2n_path="/root/support/cpa2n";
cp_a2n_backup_dir="$cp_a2n_path/backups"
cp_a2n_log="$cp_a2n_path/cp_a2n-$(date +"%m%d%Y")-$(date +%s | sha256sum | base64 | head -c 6).log";

# Initial option/variable. Catch the domain from input
migrating_addon_domain="$1";

# Variables in alphabetical order
addon_details=$(grep "$migrating_addon_domain" /etc/userdatadomains |grep addon |sed "s/==/\n/g");
addon_domains=$(grep addon /etc/userdatadomains |awk '{print $1}' |sed 's/://g');
addon_docroot=$(echo "$addon_details" |awk 'FNR == 5 {print $1}');
addon_owner=$(echo "$addon_details" |awk '{print $2}');
addon_subdomain=$(echo "$addon_details" |awk 'FNR == 4 {print $1}');
addon_vhost=$(echo "$addon_details" |awk 'FNR == 6 {print $1}');

new_useracc=$(echo "$(echo "$migrating_addon_domain" |cut -c1-7)acc");
new_userpass=$(cat /dev/urandom | tr -cd "[[:alnum:]]\.\-_\!" | head -c 12);

# Initial variable for checks
new_conf_check="0";
proceed="0";
processed="0";

# Initial variables for user exception / error in alphabetical order
addon_domain_removed="0";
addon_subdomain_removed="0";

backup_extracted="0";
backup_tar_moved="0";

copied_publichtml_content="0";
created_backup="0";
created_backup_dir="0";
created_newacc="0";
crons_removed_from_owner="0";

db_content_imported="0";

email_files_copied="0";
email_files_permed="0";
existing_backup="0";

file_ownership_reset="0";

new_crons_created="0";
new_db_created="0";
new_db_grants="0";
new_db_user_created="0";

placeholder_domain_changed="0";

##
## Functions
##

function pass(){ 
    echo -e "\033[32m✓ \033[00m $1";
    unset OUTPUT
};

function fail(){ 
    echo -e "\033[31m✘ \033[00m $1";
    unset OUTPUT;
};

####
#### Functions
#### 	>> Initial Checks
####

function is_input(){
	# Was a domain to migrate provided? 
	if [[ -z "$migrating_addon_domain" ]]; then 
		fail "No addon domain provided to migrate. See readme.";
	else
		pass "Addon domain for migration provided: $migrating_addon_domain";
			proceed="1";
	fi	
};

function is_cpanel(){
# Is it a cPanel server?
	if [[ -f /etc/init.d/cpanel ]]; then 
		pass "This is a cPanel server.";
	elif [[ -f /etc/systemd/system/cpanel.service ]]; then 
		pass "This is a cPanel server.";
	else 
		fail "Unable to confirm this is a cPanel server.";
			proceed="0";
	fi
};

function is_ahash(){
# Is there an accesshash for the json-api call?
	if [[ ! -f /root/.accesshash ]]; then 
		/usr/local/cpanel/bin/mkaccesshash;
	fi
	a_hash="$(cat /root/.accesshash |sed ':a;N;$!ba;s/\n//g')";
	if [[ -f /root/.accesshash ]]; then
		pass "Accesshash available.";
	fi
};

function is_addon(){
# Does the addon domain exist?
	if [[ -z "$(echo "$addon_domains" |grep $migrating_addon_domain)" ]]; then 
		fail "Can not find $migrating_addon_domain is this server's addon domains."; 
			proceed="0";
	else
		echo " ";
		echo "+===================================+";
		echo "| Addon Domain Info                 |"; 
		echo "+===================================+";
		echo "| Addon Domain: $migrating_addon_domain";
		echo "| Primary cPanel Account: $addon_owner";
		echo "| Docroot: $addon_docroot";
		echo "| IP:port: $addon_vhost";
		echo "+===================================+";
		echo " ";
		echo "Initiating the addon > new account process now.";
			proceed="1";
	fi
};

####
#### Functions
#### 	>> Processing Steps
####

# Check for/create dir paths needed.
function is_dirs(){
	if [ ! -d $cp_a2n_path ]; then 
		mkdir -p $cp_a2n_path;
	fi
	if [ ! -d $cp_a2n_backup_dir ]; then 
		mkdir -p $cp_a2n_backup_dir;
	fi
}

# Step 1: Create a backup
function create_backup(){
# Check for existing backup, move if it exists.
	if [[ -f "/home/cpmove-$addon_owner.tar.gz" ]]; then 
		echo "Account has an existing backup, moving it to $cp_a2n_backup_dir";
		mv "/home/cpmove-$addon_owner.tar.gz" "$cp_a2n_backup_dir/";
			existing_backup="1";
	fi
	
	echo "Creating the initial backup now. This may take a while.";
		pkgacctfile=$(/scripts/pkgacct "$addon_owner" |grep -Po "pkgacctfile is: (.*?).gz");
	echo " ";
	echo "+===================================+";
	echo "| $pkgacctfile ";
	echo "+===================================+";
	echo " ";

	if [[ -f "/home/cpmove-$addon_owner.tar.gz" ]]; then
		pass "Backup created successfully. Proceeding.";
		echo " ";
			created_backup="1";
	else	
		fail "Backup creation failed. Unable to proceed.";
			proceed="0";
	fi
};

# Step 2: Create a new account
function create_newacc(){
	echo "y" | /scripts/createacct "cpao2acc-$migrating_addon_domain" "$new_useracc" "$new_userpass" |tail -n50 |grep -e '+\||'; # Considered using the API call here. However, output from CLI wwwact is nice.
		if [[ -f "/var/cpanel/users/$new_useracc" ]]; then
			echo " ";
			pass "New account $new_useracc created successfully. Proceeding.";
				created_newacc="1";
		else
			fail "New account creation failed. Unable to proceed.";
				proceed="0";
		fi
};

# Step 3: Extract the backup
function extract_backup(){
	mkdir -p "/home/backup-$addon_owner";
		created_backup_dir="1";
	mv "/home/cpmove-$addon_owner.tar.gz" "/home/backup-$addon_owner";
		backup_tar_moved="1";
	cd "/home/backup-$addon_owner" || exit;
	tar -xf "cpmove-$addon_owner.tar.gz";
		pass "Backup successfully extracted.";
			backup_extracted="1";
	cd "cpmove-$addon_owner/homedir" || exit;
	cp -R "$(echo $addon_docroot |sed "s/\/home\/$addon_owner\///g")"/* "/home/$new_useracc/public_html/";
		pass "Successfully copied public_html content.";
			copied_publichtml_content="1";
}

# Step 4: Import the databases
## This is tricky, we've got to determine which SQL databases actually belong to the add-on without any user input. 
## For now, this tool will only support 1 mysql database per addon_domain.
## Also need to include option to define this as an argument (as well as many other options).
function import_mydb(){
	owner_mysqldbs=$(ls "/home/backup-$addon_owner/cpmove-$addon_owner/mysql/"*.sql |grep -v roundcube |sed "s/\/home\/backup-$addon_owner\/cpmove-$addon_owner\/mysql\///g" |sed 's/.sql//g');
		for owner_mysqldb in $(echo "$owner_mysqldbs"); do 
			if [[ ! -z $(grep -i -Rl "$owner_mysqldb" "/home/$new_useracc/public_html/") ]]; then
				addon_mysqldb="$owner_mysqldb";
				addon_mysqldb_conf=$(readlink -f $(grep -i -Rl "$addon_mysqldb" "/home/$new_useracc/public_html/"));
				owner_mysqldb_prefix=$(echo "$addon_mysqldb" |awk -F_ '{print $1}');
				owner_mysqldb_user=$(grep -i db_user $addon_mysqldb_conf |grep -Po "\'$owner_mysqldb_prefix(.*?)\'" |sed "s/'//g");
				owner_mysqldb_pass=$(grep -i db_pass $addon_mysqldb_conf |awk -F\' '{print $4}');
				
				# Extra verbosey output for debug.
				echo " ";
				echo "+===================================+";
				echo "| Old Account DB Info               |";
				echo "+===================================+";
				echo "| MySQL User Prefix: $owner_mysqldb_prefix";
				echo "| Actual MySQL DB: $addon_mysqldb";
				echo "| MySQL User: $owner_mysqldb_user";
				echo "| MySQL Password: $owner_mysqldb_pass";
				echo "+===================================+";
				echo " ";

				pass "Found the $addon_mysqldb database for $addon_mysqldb_conf. Proceeding.";
			fi
		done
			if [[ -z $addon_mysqldb ]]; then
				## Should prompt if user would like to continue or declare one.
				echo "No called database was found.";
			else
				addon_newmysqldb_prefix=$(echo "$new_useracc" |cut -b1-8);
				addon_newmysqldb=$(echo "$addon_mysqldb" |sed "s/$owner_mysqldb_prefix/$addon_newmysqldb_prefix/g");
				addon_newmysqldb_user=$(echo "$owner_mysqldb_user" |sed "s/$owner_mysqldb_prefix/$addon_newmysqldb_prefix/g");
				addon_newmysqldb_pass=$(cat /dev/urandom | tr -cd "[[:alnum:]]\.\-_\!" | head -c 12);

				# Create the new DB
				#echo "curl -ks -X GET -H \"Authorization: WHM root:$a_hash\" \"https://$(hostname -i):2087/json-api/cpanel?cpanel_jsonapi_user=$new_useracc&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=MysqlFE&cpanel_jsonapi_func=createdb&db=$addon_newmysqldb"; #DEBUG
				newdb_result=$(curl -ks -X GET -H "Authorization: WHM root:$a_hash" "https://$(hostname -i):2087/json-api/cpanel?cpanel_jsonapi_user=$new_useracc&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=MysqlFE&cpanel_jsonapi_func=createdb&db=$addon_newmysqldb" |grep -Po "result\":(\d{1})" |grep -o '[0-9]');
				sleep 3s;
					if [[ $newdb_result == 1 ]]; then
						pass "Created new database.";
						new_db_created="1";
					else
						fail "Failed to create the new database.";
						echo "Trying again...";
							retry_newdb_result=$(curl -ks -X GET -H "Authorization: WHM root:$a_hash" "https://$(hostname -i):2087/json-api/cpanel?cpanel_jsonapi_user=$new_useracc&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=MysqlFE&cpanel_jsonapi_func=createdb&db=$addon_newmysqldb");
							sleep 3s;
							retry_newdb_result_num=$(echo $retry_newdb_result |grep -Po "result\":(\d{1})" |grep -o '[0-9]');
								if [[ $retry_newdb_result_num == 1 ]]; then
									pass "Worked this time. Created new database.";
									new_db_created="1";
								else
									fail "Failed again...";
									echo "cPanel API Response:";
									echo "$retry_newdb_result";
									echo "";
									proceed="0";
								fi
					fi

				# Create the new DB_USER
				#echo "curl -ks -X GET -H \"Authorization: WHM root:$a_hash\" \"https://$(hostname -i):2087/json-api/cpanel?cpanel_jsonapi_user=$new_useracc&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=MysqlFE&cpanel_jsonapi_func=createdbuser&dbuser=$addon_newmysqldb_user&password=$addon_newmysqldb_pass"; #DEBUG
				newdb_user_result=$(curl -ks -X GET -H "Authorization: WHM root:$a_hash" "https://$(hostname -i):2087/json-api/cpanel?cpanel_jsonapi_user=$new_useracc&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=MysqlFE&cpanel_jsonapi_func=createdbuser&dbuser=$addon_newmysqldb_user&password=$addon_newmysqldb_pass" |grep -Po "result\":(\d{1})" |grep -o '[0-9]');
				sleep 3s;
					if [[ $newdb_user_result == 1 ]]; then
						pass "Created new database user.";
						new_db_user_created="1";
					else
						fail "Failed to create the new database user.";
						echo "Trying again...";
							retry_newdb_user_result=$(curl -ks -X GET -H "Authorization: WHM root:$a_hash" "https://$(hostname -i):2087/json-api/cpanel?cpanel_jsonapi_user=$new_useracc&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=MysqlFE&cpanel_jsonapi_func=createdbuser&dbuser=$addon_newmysqldb_user&password=$addon_newmysqldb_pass");
							sleep 3s;
							retry_newdb_user_result_num=$(echo $retry_newdb_user_result |grep -Po "result\":(\d{1})" |grep -o '[0-9]');
								if [[ $retry_newdb_user_result_num == 1 ]]; then
									pass "Worked this time. Created new database user.";
									new_db_user_created="1";
								else
									fail "Failed again...";
									echo "cPanel API Response:";
									echo "$retry_newdb_user_result";
									echo "";
									proceed="0";
								fi
					fi
				
				# Grant all pivs to DB_USER on DB
				#echo "curl -ks -X GET -H \"Authorization: WHM root:$a_hash\" \"https://$(hostname -i):2087/json-api/cpanel?cpanel_jsonapi_user=$new_useracc&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=MysqlFE&cpanel_jsonapi_func=setdbuserprivileges&db=$addon_newmysqldb&dbuser=$addon_newmysqldb_user&privileges=UPDATE%2CALTER"; #DEBUG
				newdb_privs_result=$(curl -ks -X GET -H "Authorization: WHM root:$a_hash" "https://$(hostname -i):2087/json-api/cpanel?cpanel_jsonapi_user=$new_useracc&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=MysqlFE&cpanel_jsonapi_func=setdbuserprivileges&db=$addon_newmysqldb&dbuser=$addon_newmysqldb_user&privileges=UPDATE%2CALTER" |grep -Po "result\":(\d{1})" |grep -o '[0-9]');
				sleep 3s;
					if [[ $newdb_privs_result == 1 ]]; then
						pass "Granted all privileges to $addon_newmysqldb_user on $addon_mysqldb.";
						new_db_grants="1";
					else
						fail "Failed to create the new database user.";
						echo "Trying again...";
							retry_newdb_privs_result=$(curl -ks -X GET -H "Authorization: WHM root:$a_hash" "https://$(hostname -i):2087/json-api/cpanel?cpanel_jsonapi_user=$new_useracc&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=MysqlFE&cpanel_jsonapi_func=setdbuserprivileges&db=$addon_newmysqldb&dbuser=$addon_newmysqldb_user&privileges=UPDATE%2CALTER");
							sleep 3s;
							retry_newdb_privs_result_num=$(echo $retry_newdb_privs_result_num |grep -Po "result\":(\d{1})" |grep -o '[0-9]');
								if [[ $retry_newdb_privs_result_num == 1 ]]; then
									pass "Worked this time. Granted all privileges to $addon_newmysqldb_user on $addon_mysqldb.";
									new_db_grants="1";
								else
									fail "Failed again...";
									echo "cPanel API Response:";
									echo "$retry_newdb_privs_result";
									echo "";
									proceed="0";
								fi
					fi

				# Extra verbosey output for debug.
				echo " ";
				echo "+===================================+";
				echo "| New Account DB Info               |";
				echo "+===================================+";
				echo "| MySQL User Prefix: $addon_newmysqldb_prefix";
				echo "| Actual MySQL DB: $addon_newmysqldb";
				echo "| MySQL User: $addon_newmysqldb_user";
				echo "| MySQL Password: $addon_newmysqldb_pass";
				echo "+===================================+";
				echo " ";

				# Import the database backups.
				if [[ -f "/home/backup-$addon_owner/cpmove-$addon_owner/mysql/$owner_mysqldb.sql" ]]; then
					mysql $addon_newmysqldb < "/home/backup-$addon_owner/cpmove-$addon_owner/mysql/$owner_mysqldb.sql";
						echo "Imported the backup database to the new database.";
							db_content_imported="1";
				else
					fail "Can not find /home/backup-$addon_owner/cpmove-$addon_owner/mysql/$owner_mysqldb.sql.";
					proceed="0";
				fi
			fi
};

### Need to do some sort of verification check here.
function check_dbimport(){
	if [[ -d "/var/lib/mysql/$addon_newmysqldb" ]]; then
		new_db_files=$(ls /var/lib/mysql/$addon_newmysqldb |grep -v "/" |grep -v ".opt");
			if [[ ! -z "$new_db_files" ]]; then
				pass "New database created successfully. Proceeding.";
					proceed="1";
			else
				fail "New database appears empty.";
					proceed="0";
			fi
	else
		fail "The new database directory does not exist.";
			proceed="0";
	fi
};

# Step 5: Update cron paths 
## No way to really know if/which one belongs to the addon.
## Only check performed here is if the cron calls the url.
function update_crons(){
	user_cronsjobs=$(grep -i "$migrating_addon_domain" "/home/backup-$addon_owner/cpmove-$addon_owner/cron/*" 2>/dev/null); # Redirect output to /dev/null
	if [[ -z "$user_cronsjobs" ]]; then 
		echo "No matching cron jobs for $migrating_addon_domain were found. Proceeding...";
	else
		echo "The following matching cron jobs were found:";
		echo "$user_cronsjobs";
		echo "Copying crons to the new account.";
			echo "$user_cronsjobs" >> "/var/spool/cron/$new_useracc";
				new_crons_created="1";
		echo "Removing crons from the $addon_owner cPanel account crons.";
			user_cronjobs_remain=$(diff -c "/var/spool/cron/$addon_owner" "/var/spool/cron/$new_useracc" |grep '^\- ' |sed 's/\- //g');
			echo "$user_cronsjobs_remain" >> "/var/spool/cron/$addon_owner.remain";
			mv "/var/spool/cron/$addon_owner" "$cp_a2n_backup_dir/$addon_owner.cronbak";
			mv "/var/spool/cron/$addon_owner.remain" "/var/spool/cron/$addon_owner";
				crons_removed_from_owner="1";
		echo "Complete. Proceeding.";
	fi
};

# Step 6: Change file ownership
function update_owner(){
	find "/home/$new_useracc/public_html" -uid 0 -exec chown "$new_useracc":"$new_useracc" {} +;
		file_ownership_reset="1";
};

# Step 7: Confirm that the account functions
function function_prompt(){
## Until I can determine a decent way to properly check functionality (automated), must prompt the user.
##
## THIS IS BROKEN
## Have you confirmed that the new account functions properly? Y✘  You must confirm before continuing. The script is now dead.
##
##
	echo "You must confirm the new account functions. Providing [[n/N]] here will kill the script.";
	read -p "Have you confirmed that the new account functions properly? " -n 1 -r
		if [[ $REPLY =~ ^[[Yy]]$ ]]; then
			proceed="1";
		else 
			proceed="0";
			fail "You must confirm before continuing. The script is now dead.";
		fi
};

# Step 8: Remove the addon domain
function remove_addon(){
## Going to need a prompt here before continuing.
# disabling currently due to #6
#	echo "You confirmed the new account functions. Providing [[n/N]] here will prevent the rest of the script from functioning properly.";
#	read -p "Would you like to remove the addon domain from the $addon_owner account? " -n 1 -r	
#		if [[ $REPLY =~ ^[[Yy]]$ ]]; then
remove_addon_result=$(curl -ks -X GET -H "Authorization: WHM root:$a_hash" "https://$(hostname -i):2087/json-api/cpanel?cpanel_jsonapi_user=$addon_owner&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=AddonDomain&cpanel_jsonapi_func=deladdondomain&domain=$migrating_addon_domain&subdomain=$addon_subdomain" |grep -Po "event\":{\"result\":(\d{1})" |grep -o '[0-9]');
	if [[ $remove_addon_result == 1 ]]; then
		pass "Addon domain and subdomain have been removed.";
		addon_domain_removed="1"; addon_subdomain_removed="1";
		proceed="1";
	else
		fail "Failed to remove the addon and subdomain.";
		echo "Trying again...";
			retry_remove_addon_result=$(curl -ks -X GET -H "Authorization: WHM root:$a_hash" "https://$(hostname -i):2087/json-api/cpanel?cpanel_jsonapi_user=$addon_owner&cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=AddonDomain&cpanel_jsonapi_func=deladdondomain&domain=$migrating_addon_domain&subdomain=$addon_subdomain" |grep -Po "event\":{\"result\":(\d{1})" |grep -o '[0-9]');
			retry_remove_addon_result_num=$(echo $retry_remove_addon_result_num |grep -Po "result\":(\d{1})" |grep -o '[0-9]');
				if [[ $retry_remove_addon_result_num == 1 ]]; then
					pass "Worked this time. Addon domain and subdomain have been removed.";
					addon_domain_removed="1"; addon_subdomain_removed="1";
					proceed="1";
				else
					fail "Failed again...";
					echo "cPanel API Response:";
					echo "$retry_remove_addon_result";
					echo "";
					proceed="0";
				fi
	fi
#		else 
#			fail "The addon domain must be removed for the rest of the script to function properly. The script is now dead.";
#				proceed="0";
#		fi	
};		

# Step 9: Change the placeholder domain's name
function change_placeholder(){
	change_placeholder_result=$(curl -ks -X GET -H "Authorization: WHM root:$a_hash" "https://$(hostname -i):2087/json-api/modifyacct?api.version=1&user=$new_useracc&DNS=$migrating_addon_domain" |grep -Po "result\":(\d{1})" |grep -o '[0-9]');
		if [[ $change_placeholder_result == 1 ]]; then
			pass "$migrating_addon_domain successfully renamed.";
			echo "Output from /etc/userdomains:";
			grep "$new_useracc" /etc/userdomains;
			echo "";
			placeholder_domain_changed="1"; processed="1";
		else
			fail "Failed to rename $migrating_addon_domain properly.";
			echo "Trying again...";
				retry_change_placeholder_result=$(curl -ks -X GET -H "Authorization: WHM root:$a_hash" "https://$(hostname -i):2087/json-api/modifyacct?api.version=1&user=$new_useracc&DNS=$migrating_addon_domain");
				retry_change_placeholder_result_num=$(echo $retry_change_placeholder_result_num |grep -Po "result\":(\d{1})" |grep -o '[0-9]');
					if [[ $retry_change_placeholder_result_num == 1 ]]; then
						pass "Worked this time. $migrating_addon_domain successfully renamed.";
						echo "Output from /etc/userdomains:";
						grep "$new_useracc" /etc/userdomains;
						placeholder_domain_changed="1"; processed="1";
					else
						fail "Failed again...";
						echo "cPanel API Response:";
						echo "$retry_change_placeholder_result";
						echo "";
						proceed="0";
					fi
		fi
};

# Step 10: Copy over email account information
function copy_email(){
	echo "Copying email account data.";
	cp /home/backup-$addon_owner/cpmove-$addon_owner/va/$addon_domain /etc/valiases/ 2>/dev/null; 
	cp /home/backup-$addon_owner/cpmove-$addon_owner/vf/$addon_domain /etc/vfilters/ 2>/dev/null;
	cp /home/backup-$addon_owner/cpmove-$addon_owner/homedir/.autorespond/*$addon_domain* /home/$new_useracc/.autorespond/ 2>/dev/null;
	cp -R /home/backup-$addon_owner/cpmove-$addon_owner/homedir/etc/$addon_domain /home/$new_useracc/etc/ 2>/dev/null;
	cp -R /home/backup-$addon_owner/cpmove-$addon_owner/homedir/mail/$addon_domain /home/$new_useracc/mail/ 2>/dev/null;
		email_files_copied="1";

	echo "Fixing email data permissions.";
	chown $new_useracc:mail /etc/valiases/$addon_domain 2>/dev/null;
	chown $new_useracc:mail /etc/vfilters/$addon_domain 2>/dev/null;
	chown $new_useracc:$new_useracc /home/$new_useracc/.autorespond/*$addon_domain* 2>/dev/null;
	find /home/$new_useracc/etc -uid 0 -exec chown $new_useracc:mail {} + 2>/dev/null;
	find /home/$new_useracc/mail -uid 0 -exec chown $new_useracc:mail {} + 2>/dev/null;
		pass "Email content migrated.";
			email_files_permed="1";
};

function update_newacc_conf(){
	cp "$addon_mysqldb_conf" "$addon_mysqldb_conf.old";
	echo "Correcting $migrating_addon_domain config file with the new MySQL information.";
	esc_owner_mysqldb_pass=$(echo "$owner_mysqldb_pass" |sed -e 's/[]\/$*.^|[]/\\&/g');
	esc_addon_newmysqldb_pass=$(echo "$addon_newmysqldb_pass" |sed -e 's/[\/&]/\\&/g');
	sed -i "s/$addon_mysqldb/$addon_newmysqldb/g" "$addon_mysqldb_conf";
	sed -i "s/$owner_mysqldb_user/$addon_newmysqldb_user/g" "$addon_mysqldb_conf";
	sed -i "s/$esc_owner_mysqldb_pass/$esc_addon_newmysqldb_pass/g" "$addon_mysqldb_conf";
		if [[ ! -z $(grep "$addon_newmysqldb" "$addon_mysqldb_conf") ]]; then
			new_conf_check=$(($new_conf_check+1));
		fi
		if [[ ! -z $(grep "$addon_newmysqldb_user" "$addon_mysqldb_conf") ]]; then
			new_conf_check=$(($new_conf_check+1));
		fi
		if [[ ! -z $(grep "$addon_newmysqldb_pass" "$addon_mysqldb_conf") ]]; then
			new_conf_check=$(($new_conf_check+1));
		fi		
		if [[ $new_conf_check == 3 ]]; then
			pass "New config file has been updated with the corrected/new MySQL information.";
			echo "";
			proceed="1";
		else
			fail "Something went wrong while updating $addon_mysqldb_conf";
			echo "This is not a fatal error, make sure you go back and correct this.";
			echo "";
			proceed="1";
		fi
	update_owner;
}

# Run cleanups
function cleanup(){
	# Remove all created backups, extracted tar balls, etc
	echo "Cleanup would run now.."; # Obviously doing nothing right now.
	echo "";
	pass "All done.";
};

##
## Begin executing step functions.
##

is_input;

# Eventually loop this. Leave line by line for testing for now.

if [[ $proceed == 1 ]]; then is_cpanel; fi
if [[ $proceed == 1 ]]; then is_ahash; fi
if [[ $proceed == 1 ]]; then is_addon; fi
if [[ $proceed == 1 ]]; then is_dirs; fi
if [[ $proceed == 1 ]]; then create_backup; fi
if [[ $proceed == 1 ]]; then create_newacc; fi
if [[ $proceed == 1 ]]; then extract_backup; fi
if [[ $proceed == 1 ]]; then import_mydb; fi
if [[ $proceed == 1 ]]; then check_dbimport; fi
if [[ $proceed == 1 ]]; then update_crons; fi
if [[ $proceed == 1 ]]; then update_owner; fi
# if [[ $proceed == 1 ]]; then function_prompt; fi
# disabling currently due to #6
if [[ $proceed == 1 ]]; then remove_addon; fi
if [[ $proceed == 1 ]]; then change_placeholder; fi
if [[ $proceed == 1 ]]; then copy_email; fi
if [[ $proceed == 1 ]]; then update_newacc_conf; fi
if [[ $proceed == 1 ]]; then cleanup; fi

##
## Bashtrap for reverting on breaking input.
##

trap bashtrap INT
bashtrap () {
    if [[ $processed == 1 ]]; then
        echo "Process beyond revertable point. Can not exit.";
    else
        # Loop through all initial variables for any that changed from 0 > 1, find matching revert function and execute
        # Revert functions WIP todo
        cleanup;
        echo "Not doing anything yet. Just passing the tests.";
    fi
}