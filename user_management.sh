#!/bin/bash

# Check if run as root
if [ "$EUID" -ne 0 ]; then
  dialog --msgbox "Please run this script as an administrator!" 8 50
  clear
  exit 1
fi

LOG_FILE="/var/log/g20_user_management.log"
BACKUP_DIR="/var/backups/g20_users"

mkdir -p "$BACKUP_DIR"  # Ensure backup folder exists

log_action() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

welcome_screen() {
  dialog --title "🚀 Welcome to G20 Management System" \
         --msgbox "👋 Hello Admin!\n\nManage Linux users easily and safely.\n\nPress OK to continue..." 10 50
  log_action "Admin logged into User Management System"
}

add_user() {
  username=$(dialog --inputbox "Enter new username:" 8 50 3>&1 1>&2 2>&3)
  [ -z "$username" ] && { dialog --msgbox "Username cannot be empty!" 6 40; return; }

  if id "$username" &>/dev/null; then
    dialog --msgbox "User '$username' already exists!" 6 40
  else
    password=$(dialog --passwordbox "Enter password for $username:" 8 50 3>&1 1>&2 2>&3)
    confirm_password=$(dialog --passwordbox "Confirm password for $username:" 8 50 3>&1 1>&2 2>&3)

    if [ "$password" != "$confirm_password" ]; then
      dialog --msgbox "Passwords do not match! Try again." 6 40
      return
    fi

    useradd -m "$username"
    if [ $? -eq 0 ]; then
      echo "$username:$password" | chpasswd
      dialog --msgbox "✅ User '$username' added successfully!" 6 50
      log_action "User added: $username"
    else
      dialog --msgbox "❌ Failed to add user!" 6 40
      log_action "Failed to add user: $username"
    fi
  fi

}
delete_user() {
  username=$(dialog --inputbox "Enter username to delete:" 8 50 3>&1 1>&2 2>&3)
  [ -z "$username" ] && { dialog --msgbox "Username cannot be empty!" 6 40; return; }

  if id "$username" &>/dev/null; then
    dialog --yesno "Are you sure you want to delete user '$username'?" 7 60
    if [ $? -eq 0 ]; then
      timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
      backup_path="$BACKUP_DIR/${username}_backup_$timestamp"
      mkdir -p "$backup_path"

      home_dir=$(eval echo ~"$username")
      backup_status="Backup Failed"

      # Check if the home directory exists before trying to back it up
      if [ -d "$home_dir" ]; then
        if cp -a "$home_dir/." "$backup_path/" 2>/dev/null; then
          backup_status="Backup Created"
        else
          echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Failed to copy files from $home_dir" >> "$LOG_FILE"
          backup_status="Backup Failed (copy error)"
        fi
      else
        # If no home directory, log an empty backup
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Warning: No home directory found for $username, created empty backup." >> "$LOG_FILE"
        backup_status="Empty Backup (no home dir)"
        mkdir -p "$backup_path"  # Ensure the backup folder exists even if no files are copied
      fi

      # Proceed with user deletion
      userdel -r "$username" 2>>"$LOG_FILE"
      dialog --msgbox "✅ User '$username' deleted." 6 40
      log_action "User deleted: $username ($backup_status)"
    fi
  else
    dialog --msgbox "User '$username' does not exist!" 6 40
  fi
}



restore_user() {
  backups=$(ls "$BACKUP_DIR" 2>/dev/null)
  if [ -z "$backups" ]; then
    dialog --msgbox "❌ No backups found in $BACKUP_DIR." 6 50
    return
  fi

  selected_backup=$(dialog --menu "Select a backup to restore:" 15 60 6 $(echo "$backups" | awk '{print NR, $1}') 3>&1 1>&2 2>&3)
  [ -z "$selected_backup" ] && return

  backup_folder=$(echo "$backups" | sed -n "${selected_backup}p")
  username=$(echo "$backup_folder" | cut -d'_' -f1)
  backup_path="$BACKUP_DIR/$backup_folder"

  if [ ! -d "$backup_path" ]; then
    dialog --msgbox "❌ Backup folder '$backup_path' not found!" 6 60
    log_action "Restore failed: $username (missing backup folder)"
    return
  fi

  if id "$username" &>/dev/null; then
    dialog --msgbox "⚠️ User '$username' already exists. Cannot restore." 6 50
    return
  fi

  useradd -m "$username"
  if [ $? -ne 0 ]; then
    dialog --msgbox "❌ Failed to create user '$username'." 6 50
    log_action "Failed to restore user: $username (useradd failed)"
    return
  fi

  if [ "$(ls -A "$backup_path")" ]; then
    cp -a "$backup_path/." "/home/$username/" 2>>"$LOG_FILE"
    chown -R "$username":"$username" "/home/$username/"
    restore_status="Restored with files"
  else
    restore_status="Restored (empty backup)"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Warning: Restored '$username' with empty backup folder." >> "$LOG_FILE"
  fi

  dialog --msgbox "✅ User '$username' restored from backup." 6 50
  log_action "User restored: $username ($restore_status from $backup_folder)"
}

modify_user() {
  username=$(dialog --inputbox "Enter username to modify:" 8 50 3>&1 1>&2 2>&3)
  [ -z "$username" ] && { dialog --msgbox "Username cannot be empty!" 6 40; return; }

  if id "$username" &>/dev/null; then
    action=$(dialog --menu "Select modification for $username:" 12 50 3 \
      1 "Change Username" \
      2 "Change Password" \
      3 "Lock/Unlock Account" 3>&1 1>&2 2>&3)

    case $action in
      1)
        new_username=$(dialog --inputbox "Enter new username:" 8 50 3>&1 1>&2 2>&3)
        if [ -n "$new_username" ]; then
          usermod -l "$new_username" "$username"
          dialog --msgbox "✅ Username changed from '$username' to '$new_username'." 6 50
          log_action "Username changed: $username -> $new_username"
        else
          dialog --msgbox "New username cannot be empty!" 6 40
        fi
        ;;
      2)
        new_password=$(dialog --passwordbox "Enter new password for $username:" 8 50 3>&1 1>&2 2>&3)
        if [ -n "$new_password" ]; then
          echo "$username:$new_password" | chpasswd
          dialog --msgbox "✅ Password changed for '$username'." 6 50
          log_action "Password changed for: $username"
        else
          dialog --msgbox "Password cannot be empty!" 6 40
        fi
        ;;
      3)
        lock_choice=$(dialog --menu "Lock or Unlock user account:" 10 50 2 \
          1 "Lock Account" \
          2 "Unlock Account" 3>&1 1>&2 2>&3)

        if [ "$lock_choice" == "1" ]; then
          usermod -L "$username"
          dialog --msgbox "🔒 User '$username' locked." 6 40
          log_action "User locked: $username"
        elif [ "$lock_choice" == "2" ]; then
          usermod -U "$username"
          dialog --msgbox "🔓 User '$username' unlocked." 6 40
          log_action "User unlocked: $username"
        fi
        ;;
    esac
  else
    dialog --msgbox "User '$username' does not exist!" 6 40
  fi
}

list_users() {
  users=$(awk -F: '$3 >= 1000 && $1 != "nobody" { print "👤  " $1 }' /etc/passwd | sort)
  dialog --msgbox "List of Active Users:\n\n$users" 20 60
  log_action "Viewed user list"
}

view_stats() {
  total_users=$(awk -F: '$3 >= 1000 && $1 != "nobody" { count++ } END { print count }' /etc/passwd)
  today_added=$(grep "$(date '+%Y-%m-%d')" "$LOG_FILE" | grep -c "User added")

  dialog --msgbox "📊 User Statistics:\n\nTotal Users: $total_users\nNew Users Today: $today_added" 10 50
  log_action "Viewed statistics"
}

view_logs() {
  if [ -f "$LOG_FILE" ]; then
    dialog --textbox "$LOG_FILE" 20 70
  else
    dialog --msgbox "Log file not found!" 6 40
  fi
}

goodbye_screen() {
  dialog --title "👋 Goodbye Admin!" \
         --msgbox "Thanks for using the G20 Management System.\n\nSession closed." 10 50
  clear
  exit 0
}

show_menu() {
  dialog --clear --backtitle "🚀 G20 Bash User Management System" \
    --title "📋 G20 Admin Menu" \
    --menu "Choose an option:" 18 60 10 \
    1 "➕  Add User" \
    2 "❌  Delete User" \
    3 "✏️   Modify User" \
    4 "👤  List Users" \
    5 "📊  View Statistics" \
    6 "📜  View Logs" \
    7 "🔄  Recycle Bin" \
    8 "🚪  Exit" 2>/tmp/menu_choice

  choice=$(< /tmp/menu_choice)
}

# --- MAIN PROGRAM ---
welcome_screen

while true; do
  show_menu
  case $choice in
    1) add_user ;;
    2) delete_user ;;
    3) modify_user ;;
    4) list_users ;;
    5) view_stats ;;
    6) view_logs ;;
    7) restore_user ;;
    8) goodbye_screen ;;
    *) dialog --msgbox "Invalid option. Please try again." 6 30 ;;
  esac
done

