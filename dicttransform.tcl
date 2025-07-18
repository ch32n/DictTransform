package provide dicttransform 2.3

namespace eval dicttr {
	variable template
}

set dicttr::template(Key) {
	set KeyStatus 1
	set Key [list @Key@]
}

set dicttr::template(Start) {
	set Name @Name@
	set KeyStatus 0
	set ResData [dict create]
	set ArrayIndex 0
}

set dicttr::template(Variable) {
	SetVariable @VarName@ [dict get $Dict {*}@Key@]
}

set dicttr::template(End) {
	foreach Section {Get Flatten From Foreachkey Transform Return Filter} {
		set Config($Section) [GetConfig $Name $Section]
	}

	array set Commands  [GetConfig $Name Command]
	array set ChildProc [GetConfig $Name ChildProc]

	if [llength $Config(Transform)] {
		foreach TransformProc $ChildProc($Config(Transform)) {
			set Dict [$TransformProc $Dict]
		}
	}
	
	set Config(Flatten) [lindex $Config(Flatten) 0]
	foreach FlattenPath $Config(Flatten) {	
		if [dict exists $Dict {*}$FlattenPath] {
			set FlattenDictData [dict get $Dict {*}$FlattenPath]
			
			set Length [llength $FlattenPath]
			while {$Length} {
				set FlattenPath [lrange $FlattenPath 0 $Length-1]
				dict unset Dict {*}$FlattenPath
				
				incr Length -1
			}
			
			set Dict [dict merge $Dict $FlattenDictData]
		}
	}
	
	if {[llength $Config(Filter)] && [dicttr::FilterCmdCheck Dict $Config(Filter)]} {
		return
	}
	
	if [llength $Config(Return)] {
		return $Dict
	}	

	foreach GetKey $Config(Get) {
		set ResData [dict merge $ResData [::dicttr::GetCmdParseDict $Dict $GetKey]] 
	}

	foreach FromKey $Config(From) {			
		set ResData [dict merge $ResData [::dicttr::ParseFromDict $Dict $FromKey [namespace current]::$ChildProc($FromKey)]]
	}
	
	if [llength $Config(Foreachkey)] {
		foreach FromKey [dict keys $Dict] {
			set ResData [dict merge $ResData [::dicttr::ParseFromDict $Dict $FromKey [namespace current]::$ChildProc($Config(Foreachkey))]]
		}
	}

	foreach Command [array names Commands] {			
		set CommandResDict [try $Commands($Command)]
		set ResData [dict merge $ResData [dict create $Command [[namespace current]::$ChildProc($Command) $CommandResDict]]]
	}

	if $KeyStatus {
		set Key [dicttr::ExtractKey $Key Dict]

		if ![llength $Key] {
			return
		}		

		set ResData [dict create $Key $ResData]
	}
	
	return $ResData
}

set dicttr::template(NS_Body) {
	variable commands [list]
	#
	variable config
	array unset config
	array set config {}
	#
	variable staticVars [list]
	#
	variable VarsData
	array unset VarsData
	array set VarsData {}
	#
	proc SetStaticVars {Value} {
		variable staticVars $Value
		ClearVarData
		return
	}
	#
	proc ClearVarData {} {
		variable staticVars
		variable VarsData
		#
		array unset VarsData
		array set VarsData $staticVars
		return
	}
	#
	proc SetVariable {Var Val} {
		variable VarsData
		#
		set VarsData($Var) $Val
		return
	}
	#
	proc GetVar {Var} {
		variable VarsData
		return $VarsData($Var)
	}
	#
	proc GetConfig {Name Type} {
		variable config
		if [info exists config($Name,$Type)] {
			return $config($Name,$Type)
		}
		return
	}
	#
	proc SetConfig {Name Type Val {Arr {}}} {
		variable config
		if ![llength $Arr] {
			lappend config($Name,$Type) $Val
		} else {
			lappend config($Name,$Type) $Val $Arr
		}
		return
	}
	#
	proc parse {Dict} {
		variable commands
		#
		ClearVarData
		#
		set Command [lindex [dict keys $Dict] 0]
		#
		set ResDict [dict create]
		#
		if {$Command in $commands} {
			set ResDict [$Command $Dict]
		}
		return $ResDict
	}
}

proc dicttr::CreateTemplate {Mapping Template} {
	variable template
	return [string map $Mapping $template($Template)]
}

# Pre-processes a command string to substitute all @variable@ placeholders
# with the Tcl code required to fetch their values at runtime.
proc dicttr::MapCommandVars {Cmd} {
	foreach Var [regexp -all -inline {@.*?@} $Cmd] {
		regexp {@(.*)@} $Var -> VarName
		set VarGetCmd [string map [list @VarName@ $VarName] {[GetVar @VarName@]}]
		set Cmd [string map [list $Var $VarGetCmd] $Cmd]
	}
	return $Cmd
}

# Dynamically creates a Tcl procedure based on a declarative configuration.
# This procedure recursively builds child procedures for handling nested data structures.
proc dicttr::CreateProc {NS Name Config {Level 0}} {
    incr Level

    set ProcBody [list]
    lappend ProcBody [dicttr::CreateTemplate [list @Name@ $Name] Start]

    # Use a 'while' loop to safely consume commands and arguments
    while {[llength $Config] > 0} {
        set Command [lindex $Config 0]
        set Config [lrange $Config 1 end] ;# Consume the Command

        switch -- $Command {
            transform {
                if {$Level > 1} {
                    throw error "Error: 'transform' is only allowed at the top level (in processor '$Name')."
                }
                if {[llength [namespace inscope $NS GetConfig $Name Transform]]} {
                    throw error "Error: Multiple 'transform' commands are prohibited (in processor '$Name')."
                }
                if {[llength $Config] < 1} {
                    throw error "Error: 'transform' requires a processor name argument (in processor '$Name')."
                }

                set ChildProcName [lindex $Config 0]
                set Config [lrange $Config 1 end] ;# Consume argument

                namespace inscope $NS SetConfig $Name Transform Transform
                namespace inscope $NS SetConfig $Name ChildProc Transform $ChildProcName
            }
            from {
                if {[llength $Config] < 2} {
                    throw error "Error: 'from' requires a key and a body argument (in processor '$Name')."
                }
                set ChildKey [lindex $Config 0]
                set ChildBody [lindex $Config 1]
                set Config [lrange $Config 2 end] ;# Consume arguments

                set ChildProcName [join [list $Name {*}$ChildKey] _]
                CreateProc $NS $ChildProcName $ChildBody $Level

                namespace inscope $NS SetConfig $Name From $ChildKey
                namespace inscope $NS SetConfig $Name ChildProc $ChildKey $ChildProcName
            }
            foreachkey {
                if {[llength [namespace inscope $NS GetConfig $Name Foreachkey]]} {
                    throw error "Error: Multiple 'foreachkey' commands are prohibited (in processor '$Name')."
                }
                if {[llength $Config] < 1} {
                    throw error "Error: 'foreachkey' requires a body argument (in processor '$Name')."
                }
                set ChildBody [lindex $Config 0]
                set Config [lrange $Config 1 end] ;# Consume argument

                set ChildKey Foreachkey
                set ChildProcName "${Name}_${ChildKey}"
                CreateProc $NS $ChildProcName $ChildBody $Level

                namespace inscope $NS SetConfig $Name Foreachkey $ChildKey
                namespace inscope $NS SetConfig $Name ChildProc $ChildKey $ChildProcName
            }
            command {
                if {[llength $Config] < 3} {
                    throw error "Error: 'command' requires a key, a command string, and a body argument (in processor '$Name')."
                }
                set ChildKey [lindex $Config 0]
                set CommandStr [MapCommandVars [lindex $Config 1]]
                set ChildBody [lindex $Config 2]
                set Config [lrange $Config 3 end] ;# Consume arguments

                set ChildProcName "${Name}_${ChildKey}"
                CreateProc $NS $ChildProcName $ChildBody $Level

                namespace inscope $NS SetConfig $Name Command $ChildKey $CommandStr
                namespace inscope $NS SetConfig $Name ChildProc $ChildKey $ChildProcName
            }
            get -
            flatten -
            filter -
            key {
                if {[llength $Config] < 1} {
                    throw error "Error: '$Command' requires one argument (in processor '$Name')."
                }
                set argument [lindex $Config 0]
                set Config [lrange $Config 1 end] ;# Consume argument
                
                # Capitalize the command name for use with SetConfig
                set configType [string totitle $Command]
                
                if {$Command eq "key"} {
					lappend ProcBody [dicttr::CreateTemplate [list @Key@ $argument] Key]
				} else {
					namespace inscope $NS SetConfig $Name $configType $argument
                }
            }
            variable {
                if {[llength $Config] < 3} {
                    throw error "Error: 'variable' requires a variable name, 'from', and a key path (in processor '$Name')."
                }
                set VarName [lindex $Config 0]
                # expecting 'from' at index 1, which we can ignore
                set KeyPath [lindex $Config 2]
                set Config [lrange $Config 3 end] ;# Consume arguments

                lappend ProcBody [dicttr::CreateTemplate [list @VarName@ $VarName @Key@ $KeyPath] Variable]
            }
            return {
                namespace inscope $NS SetConfig $Name Return 1
            }
            default {
                throw error "Error: Unknown command '$Command' (in processor '$Name')."
            }
        }
    }

    # Append the final logic block and create the procedure
    lappend ProcBody [dicttr::CreateTemplate [list] End]
    proc ${NS}::$Name {{Dict {}}} [join $ProcBody \n]

    return
}

# Generates a dynamic key for reshaping data, supporting array-style indexing
# (@arrayindex@) or extraction from the key's value index.
proc dicttr::ExtractKey {KeyOptions DictVar} {
	upvar 1 $DictVar DictTmp
	
	set OptionDict [ExtractOptions $KeyOptions]
	dict with OptionDict {}	
	
	#return index of the list item if key = @arrayindex@
	if [regexp @arrayindex@ $key_path] {
		upvar 3 ArrayIndex ArrayIndexTmp
		incr ArrayIndexTmp
		
		return [expr {$ArrayIndexTmp - 1}]
	}
	
	
	if ![dict exists $DictTmp {*}$key_path] {
		return
	}	
	
	set KeyVal [dict get $DictTmp {*}$key_path]
	
	if [llength $index] {
		return [lindex $KeyVal {*}$index]
	}
	
	return $KeyVal
}

# Checks if a given dictionary passes the conditions defined in a 'filter' command,
# evaluating regexp and script-based rules.
proc dicttr::FilterCmdCheck {DictVar FilterCmds} {
	upvar $DictVar DictTmp
	
	set FilterCmds [lindex $FilterCmds 0]
	
	set ReturnVal 0
	foreach FilterCmd $FilterCmds {
		set OptionDict [ExtractOptions $FilterCmd]
		dict with OptionDict {}
		
		if ![dict exists $DictTmp {*}$key_path] {
			continue
		}
		
		set Value [dict get $DictTmp {*}$key_path]
		set Matches 1
		
		if [llength $regexp] {
			set Matches [regexp -- $regexp $Value]
		}
		
		if [llength $script] {
			#substitute %v option with value
			set script [string map [list %v \$Value] $script]
			set ScriptStatus [apply [list {Value} $script] $Value]
			
			set Matches [expr {$ScriptStatus & $Matches}]
		}
		
		set ExcludeStatus [expr {$Matches ^ $include}]
		set ReturnVal     [expr {$ReturnVal | $ExcludeStatus}]
	}
		
	return $ReturnVal
}

# Parses a single entry from a 'get' command's argument list, extracting the
# key_path, alias, default value, and all other options into a dictionary.
proc dicttr::ExtractOptions {Entry} {
    # 1. Initialize variables for all possible options
    set Option {
        key_path    {}
		index       {}
        alias       {}
        has_default 0 
		include     1 
        default     {}
        script      {}
		required    0
		map         {}
		regexp      {}
    }

    # 2. Check if the entry uses the advanced '->' syntax
	set SearchIndex [lsearch -exact $Entry "->"]
    if {$SearchIndex > 0} {
        # Entry is in the form: {key_path -> options_dict}
        dict set Option key_path [lrange $Entry 0 ${SearchIndex}-1]
        set Option_dict [lrange $Entry ${SearchIndex}+1 end]
		
        set Option [dict merge $Option $Option_dict]
		
        if {[dict exists $Option_dict default]} {
            dict set Option has_default 1
        }
    } else {
        # 3. Handle the simple form: "key" or "{nested key}"
        dict set Option key_path [lrange $Entry 0 end]
    }

    # 5. If no alias was explicitly set, derive it from the key path
    if ![llength [dict get $Option alias]] {
        dict set Option alias [dict get $Option key_path]
    }

    return $Option
}

# This procedure processes a list of "get commands" to build a new dictionary
# by extracting and transforming values from a source dictionary.
# %v is special option in script, which is substituted with value
proc dicttr::GetCmdParseDict {Dict GetCmds} {
	set RetDict [dict create]

	foreach GetCmd $GetCmds {
		# 1. Unpack all command options into local variables for easy access.
		# This avoids numerous 'dict get' calls.
		set OptionDict [ExtractOptions $GetCmd]
		dict with OptionDict {}

		# 2. Determine the initial value for the key.
		# This section handles required, missing, and default values.
		set Value ""
		if {[dict exists $Dict {*}$key_path]} {
			set Value [dict get $Dict {*}$key_path]
		} elseif {$required} {
			# Guard clause: Fail fast if a mandatory key is missing.
			throw error "Error: Field '$key_path' is required but not found"
		} elseif {$include && $has_default} {
			set Value $default
		} else {
			# Key not found and has no default. Handle special 'include' case
			# for adding an empty dict, otherwise skip this command.
			if {$include} {
				dict set RetDict {*}$alias [dict create]
			}
			continue
		}

		# 3. Apply the transformation pipeline to the value.
		if {[llength $regexp]} {
			if {[llength $regexp] != 2 || ![string is integer -strict [lindex $regexp 1]]} {
				throw error "Error: Invalid usage of regexp option for key '$key_path'"
			}
			lassign $regexp reg_pattern reg_index
			set matches [regexp -inline -- $reg_pattern $Value]
			if {[llength $matches] > $reg_index} {
				set Value [lindex $matches $reg_index]
			} elseif {$has_default} {
				# Fallback to default if regexp does not match
				set Value $default
			} else {
				if {$include} {
					dict set RetDict {*}$alias [dict create]
				}
				# No match and no default, so we can't proceed.
				continue
			}
		}

		if {[llength $map]} {
			set Value [string map -nocase $map $Value]
		}

		if [llength $script] {
			#substitute %v option with value
			set script [string map [list %v $Value] $script]
			set Value [try $script]
		}

		# 4. Set the final transformed value in the return dictionary.
		dict set RetDict {*}$alias $Value
	}
	return $RetDict
}

# Handles the logic for a 'from' command, which descends into a nested dictionary
# or list of dictionaries and applies a child transformation procedure.
proc dicttr::ParseFromDict {Dict KeyCmd ChildProc} {
	set OptionDict [ExtractOptions $KeyCmd]
	dict with OptionDict {}

	if $include {
		set ResData [dict create $alias [dict create]]
	} else {
		set ResData [dict create]
	}
	
	if [dict exists $Dict {*}$key_path] {
		if {[llength [lindex [dict get $Dict {*}$key_path] 0]] > 1} {
		
			set ResData [dict create $alias [dict create]]
			
			foreach Data [dict get $Dict {*}$key_path] {				
				dict set ResData $alias [dict merge [dict get $ResData $alias] [$ChildProc $Data]]
			}
		} else {
			dict set ResData $alias [$ChildProc [dict get $Dict {*}$key_path]]
		}
	}
	return $ResData
}

# Pre-processes the main configuration array, resolving all template
# references (e.g., %template_name%) by replacing them with their definitions.
proc dicttr::ReplaceTemplate {arrName} {
	upvar $arrName configArr
	
	set Done 0
	
	while {!$Done} {
		set Done 1
		foreach Command [array names configArr] {
			set Templates [regexp -all -line -inline {%.*%} $configArr($Command)]
			if [llength $Templates] {
				set Done 0
				
				foreach Tmplt $Templates {
					if ![info exists configArr($Tmplt)] {
						throw error "Error: No such template '${Tmplt}'."
					}
					
					set configArr($Command) [string map [list $Tmplt $configArr($Tmplt)] $configArr($Command)]
				}
			}
		}
	}
}

# The main public entry point for the library. It creates a complete transformation
# interface within a new namespace based on a declarative configuration array.
proc dicttr::create_interface {arrName args} {
	upvar $arrName configArr
	#
	variable template
	#
	set NS ::$arrName
	#
	namespace eval $NS $template(NS_Body)
	#
	ReplaceTemplate configArr
	#
	set Commands [list]
	foreach Command [lsort -dict [array names configArr]] {
		if ![regexp {%.*%} $Command] {
			lappend Commands $Command
			CreateProc $NS $Command $configArr($Command)
		}
	}
	#
	foreach {Opt Val} $args {
		switch -- $Opt {
			-staticvars {
				namespace inscope $NS SetStaticVars $Val
			}
			default {
				throw error "Error: No such option '${Opt}'"
			}
		}
	}
	#
	set ${NS}::commands $Commands
	#
	return
}

