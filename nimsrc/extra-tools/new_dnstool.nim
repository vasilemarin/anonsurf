import os
import osproc
import strutils
import net
import .. / utils / dnsutils

const
  sysResolvConf = "/etc/resolv.conf"
  bakResolvConf = "/etc/resolv.conf.bak"
  runResolvConf = "/run/resolvconf/resolv.conf"
  dhcpResolvConf = "/run/resolvconf/interface/NetworkManager"
  tailResolvConf = "/etc/resolvconf/resolv.conf.d/tail"
  DNS_STATIC = 1
  DNS_DYNAMIC = 2


proc showHelpCmd(cmd = "dnstool", keyword = "help", args = "", descr = "") =
  #[
    Make color for command syntax in help bannner
    Print them in help
    Syntax: <command> <keyword> <args> [<description>]
    command -> light green
    keyword -> red
    args (optional) -> yellow
    description (optional) -> blue
  ]#
  var cmdOutput = ""
  cmdOutput &= "\e[32m" & cmd & "\e[0m " # Green color for command
  cmdOutput &= "\e[31m" & keyword & "\e[0m " # Red color for keyword
  if args != "":
    cmdOutput &= "\e[33m" & args & "\e[0m "
  if descr != "":
    cmdOutput &= "[\e[34m" & descr & "\e[0m]"
  
  echo cmdOutput


proc banner() =
  stdout.write("DNS Tool: A CLI tool to change DNS settings quickly\n")
  stdout.write("Developer: Nong Hoang \"DmKnght\" Tu <dmknght@parrotsec.org>\n")
  stdout.write("Gitlab: https://nest.parrot.sh/packages/tools/anonsurf\n")
  stdout.write("License: GPL3\n\n")


proc showHelpDesc(keyword = "", descr = "") =
  #[
    Make color for description
    syntax:
      <keyword>: <description>
    keyword -> red
    description -> blue
  ]#
  var helpDesc = ""
  if keyword != "":
    helpDesc = "\e[31m" & keyword & "\e[0m: "
  helpDesc &= "\e[34m" & descr & "\e[0m"

  echo "  " & helpDesc


proc help() =
  banner()
  # let progName = getAppFileName()
  let progName = "dnstool"
  showHelpCmd(cmd = progName, keyword = "help | -h | --help", descr = "Show help banner")
  showHelpCmd(cmd = progName, keyword = "status", descr = "Show current system DNS")
  showHelpCmd(cmd = "sudo " & progName, keyword = "dynamic", descr = "Use DHCP's DNS")
  showHelpCmd(cmd = "sudo " & progName, keyword = "dynamic", args = "<Address[es]>", descr = "Use DHCP's DNS and custom DNS address[es]")
  showHelpCmd(cmd = "sudo " & progName, keyword = "static", args = "<Address[es]>", descr = "Use custom DNS address[es]")
  showHelpCmd(cmd = "sudo " & progName, keyword = "create-backup", descr = "Make backup for current settings in /etc/resolv.conf")
  showHelpCmd(cmd = "sudo " & progName, keyword = "restore-backup", descr = "Restore backup of /etc/resolv.conf")
  stdout.write("\nAddress could be:\n")
  showHelpDesc(keyword = "opennic", descr = "OpenNIC address[es]")
  showHelpDesc(keyword = "parrot", descr = "ParrotOS DNS address[es]")
  showHelpDesc(keyword = "dhcp", descr = "Address[es] of current DHCP settings")
  showHelpDesc(descr = "Any IPv4 or IPv6 address[es]")
  stdout.write("\nStatic and Dynamic:\n")
  showHelpDesc(keyword = "static", descr = "Keep DNS settings after reboot or join other network")
  showHelpDesc(keyword = "dynamic", descr = "Doesn't keep current address[es] after reboot or join new network")
  stdout.write("\n")


proc getParrotDNS(): string =
  #[
    Use host command to automatically get ip from director.geo.parrot.sh
    FIXME get addresses when dns is empty
    TODO use native libs instead of using subprocess
  ]#
  try:
    let output = execProcess("/usr/bin/host director.geo.parrot.sh")
    var allIP = ""
    for line in output.split("\n"):
      if line.startsWith("director.geo.parrot.sh has "):
        allIP &= "nameserver " & line.split(" ")[^1] & "\n"
      else:
        discard
    return allIP
  except:
    return ""


proc getOpenNIC(): string =
  result = "nameserver 185.121.177.177\nnameserver 169.239.202.202\n"
  result &= "nameserver 198.251.90.108\nnameserver 198.251.90.109\n"
  result &= "nameserver 198.251.90.110\n"


proc getDhcpDNS(): string =
  return readFile(dhcpResolvConf) & "\n"


proc lnkResovConf() =
  #[
    Create a symlink of /etc/resolv.conf from
    /run/resolvconf/resolv.conf
    FIXME if the system has the 127.0.0.1 in runResolvConf
  ]#
  try:
    createSymlink(runResolvConf, sysResolvConf)
  except:
    discard


proc writeTail(dnsAddr: string) =
  #[
    Create dyanmic resolv.conf
    Write tail
  ]#
  # TODO add write tail file here
  try:
    writeFile(tailResolvConf, dnsAddr)
  except:
    discard # TODO use notifcation here


proc writeResolv(dnsAddr: string) =
  #[
    Create static resolv.conf
  ]#
  let banner = "# Static resolv.conf genetared by DNSTool\n# Settings wont change after reboot\n"
  try:
    writeFile(sysResolvConf, banner & dnsAddr)
  except:
    discard


proc makeDHCPDNS() =
  try:
    removeFile(sysResolvConf)
    lnkResovConf()
  except:
    discard


proc handleMakeDNS(dnsType: int, dnsAddr: string) =
  # TODO if dnsAddr == "" : return error
  if dnsType == DNS_STATIC:
    # TODO remove old settings
    writeResolv(dnsAddr)
  else:
    # TODO remove old settings
    writeTail(dnsAddr)
    # TODO need to update config using resolvconf?


proc mkBackup() =
  #[
    Backup current settings of /etc/resolv.conf
    to /etc/resolv.conf.bak
  ]#
  # Check previous backup exists
  # Check current settings
  # skip if it is localhost or error of /etc/resolv.conf
  # or symlink
  let status = dnsStatusCheck()
  if status <= 0:
    # We are having error -> skip
    discard
  else:
    try:
      copyFile(sysResolvConf, bakResolvConf)
    except:
      discard # TODO show error here


proc restoreBackup() =
  #[
    Restore /etc/resolv.conf.bak to /etc/resolv.conf
    Or use dhcp addresses
  ]#
  let status = dnsStatusCheck()
  if status == 0:
    # AnonSurf is running so it is using localhost. skip
    discard
  elif not fileExists(bakResolvConf):
    # No backup file. We create DHCP + dynamic setting
    # If there is no resolv.conf, we create symlink
    if fileExists(sysResolvConf):
      discard
    else:
      lnkResovConf()
  else:
    # AnonSurf is not running and the backup file is there
    # If resolv.conf is there, we try remove it
    # solve symlink problem
    if status != ERROR_FILE_NOT_FOUND:
      # No resolv.conf
      if tryRemoveFile(sysResolvConf):
        moveFile(bakResolvConf, sysResolvConf)
      else:
        discard # TODO show error here
        return
    if tryRemoveFile(sysResolvConf):
      moveFile(bakResolvConf, sysResolvConf)
    else:
      discard # TODO show error here


proc showStatus() =
  #[
    Get current settings of DNS on system
  ]#
  let statusResult = dnsStatusCheck()
  var
    dnsType = ""
    dnsAddr = ""

  case statusResult
  of STT_DNS_TOR:
    stdout.write("[\e[32mSTATUS\e[0m] AnonSurf DNS\n")
  of ERROR_DNS_LOCALHOST:
    stderr.write("[\e[31mERROR\e[0m] Local host\n")
  of ERROR_FILE_NOT_FOUND:
    stderr.write("[\e[31mERROR\e[0m] resolv.conf not found\n")
  of ERROR_FILE_EMPTY:
    stderr.write("[\e[31mERROR\e[0m] resolv.conf is empty\n")
  of ERROR_UNKNOWN:
    stderr.write("[\e[31mERROR\e[0m] Runtime error: Unknown problem\n")
  of 10 .. 13:
    dnsType = "Static"
  of 20 .. 23:
    dnsType = "Dynamic"
  else:
    discard
  
  case statusResult mod 10
  of 0:
    dnsAddr = "DHCP only"
  of 1:
    dnsAddr = "OpenNIC"
  of 2:
    dnsAddr = "Custom"
  of 3:
    dnsAddr = "OpenNIC + Custom"
  else:
    discard

  if dnsType != "":
    echo "[\e[32mSTATUS\e[0m]\n- \e[31mMethod\e[0m: \e[36m" & dnsType & "\e[0m\n- \e[31mAddress\e[0m: \e[36m" & dnsAddr & "\e[0m"


proc main() =
  if paramCount() == 0:
    help()
    showStatus()
    return
  elif paramCount() == 1:
    if paramStr(1) in ["help", "-h", "--help", "-help"]:
      help()
      return
    elif paramStr(1) == "status":
      showStatus()
      return
    elif paramStr(1) == "create-backup":
      mkBackup()
      return
    elif paramStr(1) == "restore-backup":
      restoreBackup()
      showStatus()
      return
    elif paramStr(1) == "static":
      stderr.write("[!] You must provide DNS address for static\n")
      return
    elif paramStr(1) == "dynamic":
      # FIXME unknown option in test
      # handleMakeDNS(DNS_DYNAMIC, getDhcpDNS()) # Dynamic DHCP
      makeDHCPDNS()
      showStatus()
    # elif paramStr(1) != "static" or paramStr(1) != "dynamic":
    else:
      help()
      stderr.write("[!] Unknown option\n")
      return
  else:
    var
      dnsType = 0
      dnsAddr = ""
    if paramStr(1) == "static":
      dnsType = DNS_STATIC
    elif paramStr(2) == "dynamic":
      dnsType = DNS_DYNAMIC
    else:
      stdout.write("[!] Unknown option\n")
    for i in 2 .. paramCount():
      if paramStr(i) == "opennic":
        dnsAddr &= getOpenNIC()
      elif paramStr(i) == "dhcp":
        dnsAddr &= getDhcpDNS()
      elif paramStr(i) == "parrot":
        dnsAddr &= getParrotDNS()
      elif isIpAddress(paramStr(i)):
        dnsAddr &= "nameserver " & paramStr(i) & "\n"
    handleMakeDNS(dnsType, dnsAddr)
    showStatus()


main()