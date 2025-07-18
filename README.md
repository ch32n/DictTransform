# DictTransform

Tcl library designed to declaratively parse, reshape, and transform complex dictionary structures.

## Core Concepts

DictTransform lets you define a set of rules in a Tcl array. These rules specify how to parse, filter, reshape, and transform an input dictionary into a desired output structure. It's particularly useful for processing structured data from APIs.

The library works by dynamically generating parsing procedures based on definitions.

## Installation

```
package require dicttransform
```

## Command Reference

#### `::dicttr::create_interface array_name ?-staticvars {Var1 Val1 Var2 Val2 ...}?`

This command creates procedures for all the definitions specified in the array variable name.
The name of that array becomes a namespace containing the defined commands.

`-staticvars` creates mapping for variables, which can be referenced in `command` definition.

### `get`

Extracts specified keys and their values from the source dictionary. This is the primary command for pulling data into your result and supports set of transformations on the values.

```
get {
    {<key-path-list> ?->
        alias <new-name>
        include <1|0>
        default <default-value>
        required <1|0>
        map {<from1 to1 from2 to2 ...>}
        regexp {<pattern> <index>}
        script {<script-body>}?
    }
    {...}
}
```

* `alias`: Renames the key in the output dictionary to `<new-name>`.
* `include`: If set to 0, the key is excluded from the output if its source value is missing or empty. Defaults to 1.
* `default`: Provides a `<default-value>` if the key is not found in the source dictionary.
* `required`: If set to 1, raises an error if the key is not found. Defaults to 0.
* `map`: Provides a mapping dictionary to translate a value. For example, `{true 1 false 0}`.
* `regexp`: Applies a regular expression `<pattern>` to the value and extracts the submatch at the specified `<index>`.
* `script`: Executes a custom Tcl `<script-body>` to transform the value. `%v` is substituted with the key's value before execution.


### `from`

Descends into a nested dictionary at the specified `<key-path-list>` and applies a new set of rules to it.

```
from {<key-path-list> -> include <1|0> alias <new-name>} {
    <definition>
}
```

* `include`: If set to 0, the entire block is excluded from the output if the `<key-path-list>` does not exist. Defaults to 1.
* `alias`: Renames the key in the output dictionary to `<new-name>`.


### `key`

Reshapes a list of dictionaries into a key-value pair, using a specified value from within each item as its new key.

```
key ({<key-path-list> -> index <num>} | @arrayindex@)
```

* `key`: The key whose value will be used as the new key for the item.
* `index`: If the value at `<key-path-list>` is a list, this specifies which element `<num>` to use as the key.
* `@arrayindex@`: A special keyword that uses a simple incrementing integer as the key for each item, effectively converting a list to a dictionary with numeric keys.


### `foreachkey`

Iterates over every key-value pair in the current dictionary context and applies a set of rules (`<definition>`) to each one.

```
foreachkey {
    <definition>
}
```


### `flatten`

Takes the dictionary value at `<key-path-list>` and merges its contents into the current dictionary level.

```
flatten <list of key-path-list>
```


### `transform <transform-proc-list>`

Executes a pre-defined transformation procedure on the current dictionary before any other rules in the current block are applied. This allows for multi-pass transformations.

```
transform <transform-proc-list>
```


### `variable`

Extracts a value from the source dictionary at `<key-path-list>` and stores it in a temporary variable named `<variable-name>`. This variable can then be referenced in subsequent command blocks as `@<variable-name>@`.

```
variable <variable-name> from <key-path-list>
```


### `command`

Executes an arbitrary Tcl command that is expected to return a dictionary. The result is placed under a new key in the output, and a new set of rules is applied to it. Any variables defined with the `variable` command can be used within the Tcl command string.

```
command <new-key-name> <tcl-command> {
    <definition>
}
```


### `filter`

Applies a set of conditions to the current dictionary. If the conditions are not met, processing of the current item is halted. It's possible to have multiple filters.

```
filter {
    {
        <key-path-list> ->
        regexp <pattern>
        include <1|0>
        script {<script-body>}
    }
    {...}
}
```

* `regexp`: A regular expression `<pattern>` to match against the value at `<key-path-list>`.
* `include`: If set to 1 (default), processing continues if the filter matches. If set to 0, processing continues if the filter does not match.
* `script`: A Tcl `<script-body>` that must return 1 (to pass) or 0 (to fail). `%v` is substituted with the key's value before execution.


### `return`

Immediately halts processing for the current definition block and returns the dictionary in its current state. This is useful for fetching data with `command` without applying further parsing.


## Order of operation

```
transform -> flatten -> filter -> return -> get -> from -> foreachkey -> command
```


## Templating

DictTransform supports templating to help you reuse common blocks of configuration.
The library pre-processes your entire configuration to find and replace all template placeholders before building the final transformation procedures.

A template can include other templates, and they will all be resolved correctly before the final transformation procedures are created.
A template is defined like any other rule, but its name must be enclosed in percent signs (%) — this signals to the library that it is a reusable block and not a top-level transformation command.

### Template definition

```
set array_name(%template_name%) {
    <tranform definition>
}
```

### Template usage

```
set array_name(tranfrom) {
    %template_name%
}
```



## Examples

### Get examples

```tcl
set getExample(ParseEx1) {
    get {x z}
}

set getExample(ParseEx2) {
    get {
        {x -> alias xnew}
        {a -> default 3}
        {b -> include 0}
    }
}

set getExample(ParseEx3) {
    get {
        {b -> required 1}
    }
}

set getExample(ParseEx4) {
    get {
        {x -> map {val1 newVal1 val2 newVal2} default newVal3}
        {y -> regexp { {val(\d+)} 1}}
        {z -> script {
            string map {val3 newVal3} %v
        }}
    }
}

set getExample(ParseEx5) {
    get {
        {x y}
        {a b -> alias newb}
    }
}

::dicttr::create_interface getExample

set dict1 {x 1 y 1 z 2}
set dict2 {x {y 1 z 2} a {b 3 c 4}}
set dict3 {x val1 y val2 z val3}

# returns {x 1 y 1 z 2}
getExample::ParseEx1 $dict1

# returns {xnew 1 a 1}
getExample::ParseEx2 $dict1

# raises error 'Error: Field 'b' is required but not found'
getExample::ParseEx3 $dict3

# returns {x newVal1 y 2 z newVal3}
getExample::ParseEx4 $dict3

# returns {x {y 1} newb 3}
getExample::ParseEx5 $dict2
```

### From examples

```tcl
set fromExample(ParseEx1) {
    from x {
        get y
    }
    from {a -> alias aNew} {
        get c
    }
    
    from {k i -> alias t} {
        get j
    }
}

set fromExample(ParseEx2) {
    from objects {
        key name
        get {value option}
    }
}

set fromExample(ParseEx3) {
    from {objects -> alias newObjectsKey} {
        key name
        get {value option}
    }
    
    from otherObjects {
        key name
        get {value option}        
    }
    
    from {noSuchObjects -> include 0} {
        key name
        get {value option}        
    }    
}

::dicttr::create_interface fromExample

set dict1 {
    x {y 1 z 2}
    a {b 3 c 4}
    k {
        i {j 6}
        g {j 8}
    }
}

set dict2 {
    objects {
        {name name1 value value1 option option1}
        {name name2 value value2 option option2}
    }
}

# returns {x {y 1} aNew {c 4} t {j 6}}
fromExample::ParseEx1 $dict1

# returns {objects {name1 {value value1 option option1} name2 {value value2 option option2}}}
fromExample::ParseEx2 $dict2

# returns {newObjectsKey {name1 {value value1 option option1} name2 {value value2 option option2}} otherObjects {}}
# otherObjects is included as empty key and noSuchObjects is omitted
fromExample::ParseEx3 $dict2
```

### Key examples

```tcl
set keyExample(ParseEx1) {
    from objects {
        key {name -> index 1}
        get {value}
    }
}

set keyExample(ParseEx2) {
    from objects {
        key @arrayindex@
        get {name value}
    }
}

set keyExample(ParseEx3) {
    from objects {
        key {name namekey}
        get {value}
    }
}

::dicttr::create_interface keyExample

set dict1 {
    objects {
        {name {name1 name2} value value1 option option1}
        {name {name3 name4} value value2 option option2}
    }
}

set dict2 {
    objects {
        {name {namekey nameval1} value value1 option option1}
        {name {namekey nameval2} value value2 option option2}
    }
}

# returns {objects {name2 {value value1} name4 {value value2}}}
keyExample::ParseEx1 $dict1

# returns {objects {0 {name {name1 name2} value value1} 1 {name {name3 name4} value value2}}}
keyExample::ParseEx2 $dict1

# returns {objects {nameval1 {value value1} nameval2 {value value2}}}
keyExample::ParseEx3 $dict2
```

### Foreachkey examples

```tcl
set forEachKeyExample(ParseEx1) {
    from objects {
        foreachkey {
            get {value}
        }
    }
}

::dicttr::create_interface forEachKeyExample

set dict1 {
    objects {
        obj1 {value val1 name name1}
        obj2 {value val2 name name1}
        obj3 {value val3 name name1}
    }
}

# returns {objects {obj1 {value val1} obj2 {value val2} obj3 {value val3}}}
forEachKeyExample::ParseEx1 $dict1
```

### Flatten examples

```tcl
set flattenExample(ParseEx1) {
    from data {
        flatten objcets
        return
    }
}

set flattenExample(ParseEx2) {
    from data {
        flatten {objcets values}
        get {time moreObjectsKey moreValuesKey}
    }
}

::dicttr::create_interface flattenExample

set dict1 {
    data {
        time timeVal
        date dateVal
        objcets {
            moreObjectsKey {
                {id 1 name nameVal1}
                {id 2 name nameVal2}
            }
        }
        values {
            moreValuesKey {
                {id 1 value Val1}
                {id 2 value Val2}
            }
        }
    }
}

# returns
set returnData {
    data {
        time timeVal
        date dateVal
        moreObjectsKey {
            {id 1 name nameVal1}
            {id 2 name nameVal2}}
        values {
            moreValuesKey {
                {id 1 value Val1}
                {id 2 value Val2}
            }
        }
    }
}
flattenExample::ParseEx1 $dict1

# returns
set returnData {
    data {
        time timeVal
        moreObjectsKey {
            {id 1 name nameVal1}
            {id 2 name nameVal2}
        }
        moreValuesKey {
            {id 1 value Val1}
            {id 2 value Val2}
        }
    }
}
flattenExample::ParseEx2 $dict1
```

### Filter examples

```tcl
set filterExample(ParseEx1) {
    from data {
        from objcets {
            filter {
                {type -> regexp type[12]}
            }
            key id
            get {id type}
        }
    }
}

set filterExample(ParseEx2) {
    from data {
        from objcets {
            filter {
                {type -> regexp type[12]}
                {name -> regexp name2 include 0}
            }
            key id
            get {name type}
        }
    }
}

set filterExample(ParseEx3) {
    from data {
        from objcets {
            filter {
                {id -> script {
                    if {%v < 3} {
                        return 1
                    }
                    return 0
                }}
            }
            key id
            get {name type}
        }
    }
}

::dicttr::create_interface filterExample

set dict1 {
    data {
        date dateVal
        objcets {
            {id 1 type type1 name name1}
            {id 2 type type2 name name2}
            {id 3 type type3 name name3}
        }
    }
}

# returns {data {objcets {1 {id 1 type type1} 2 {id 2 type type2}}}}
filterExample::ParseEx1 $dict1

# returns {data {objcets {1 {name name1 type type1}}}}
filterExample::ParseEx2 $dict1

# returns {data {objcets {1 {name name1 type type1} 2 {name name2 type type2}}}}
filterExample::ParseEx3 $dict1
```

### Command examples

```tcl
proc device_rest_api_stub {} {
    set Result [dict create devices [dict create]]
    
    for {set DevId 1} {$DevId < 4} {incr DevId} {
        set TmpDict [dict create]
    
        dict set TmpDict device_id $DevId
        dict set TmpDict device_name name${DevId}
        
        dict lappend Result devices $TmpDict
    }
    return $Result
}
# returns {devices {{device_id 1 name name1} {device_id 2 name name2} {device_id 3 name name3}}}

proc device_interface_rest_api_stub {DevId} {
    set Result [dict create interface [dict create]]
    
    for {set IntId 1} {$IntId < 4} {incr IntId} {
        set TmpDict [dict create]
    
        dict set TmpDict device_id $DevId
        dict set TmpDict int_id $IntId
        dict set TmpDict int_name name${IntId}
        
        dict lappend Result interface $TmpDict
    }
    return $Result    
}
# returns {interface {{device_id 1 int_id 1 int_name name1} {device_id 1 int_id 2 int_name name2} {device_id 1 int_id 3 int_name name3}}}


set commandExample(ParseEx1) {
    command my_devices_key device_rest_api_stub {
        from devices {
            key device_id
            get device_name
        }
    }
}

set commandExample(ParseEx2) {
    command my_devices_key device_rest_api_stub {
        from devices {
            key device_id
            get device_name
        
            variable DevId from device_id
            command my_interface_key {device_interface_rest_api_stub @DevId@} {
                from interface {
                    key int_id
                    get {device_id int_name}
                }
            }
        }
    }
}

::dicttr::create_interface commandExample

#returns {my_devices_key {devices {1 {device_name name1} 2 {device_name name2} 3 {device_name name3}}}}
commandExample::ParseEx1

commandExample::ParseEx2
#result
set result {
my_devices_key {
    devices {
        1 {
            device_name name1
            my_interface_key {
                interface {
                    1 {
                        device_id 1
                        int_name name1
                    }
                    2 {
                        device_id 1
                        int_name name2
                    }
                    3 {
                        device_id 1
                        int_name name3
                    }
                }
            }
        }
        2 {
            device_name name2
            my_interface_key {
                interface {
                    1 {
                        device_id 2
                        int_name name1
                    }
                    2 {
                        device_id 2
                        int_name name2
                    }
                    3 {
                        device_id 2
                        int_name name3
                    }
                }
            }
        }
        3 {
            device_name name3
            my_interface_key {
                interface {
                    1 {
                        device_id 3
                        int_name name1
                    }
                    2 {
                        device_id 3
                        int_name name2
                    }
                    3 {
                        device_id 3
                        int_name name3
                    }
                }
            }
        }
    }
}
```

### Transform examples

```tcl
set tranfromExample(transformEx1) {
    from data {
        get {x a}
    }
}

set tranfromExample(ParseEx1) {
    transform transformEx1
    get {
        {data a -> alias new_key}
    }
}

::dicttr::create_interface tranfromExample

set dict1 {
    data {
        x {
            y 1
            z 2
        }
        a {
            b 3
            c 4
        }
    }
    otherdata {
        q 1
    }
}

# result {new_key {b 3 c 4}}
tranfromExample::ParseEx1 $dict1
```

### Template examples

```tcl
set templateExample(%templateEx1%) {
    get {
        {x y}
        {a b}
    }
}

set templateExample(ParseEx1) {
    from data {
        %templateEx1%
    }
}

::dicttr::create_interface templateExample

set dict1 {
    data {
        x {
            y 1
            z 2
        }
        a {
            b 3
            c 4
        }
    }
    otherdata {
        q 1
    }
}

#returns {data {x {y 1} a {b 3}}}
templateExample::ParseEx1 $dict1
```

### Complex example
```tcl
package require dicttransform

set junosParse(%tmplt_bgp-rib_pre%) {
    from bgp-rib {
        key {name -> index {0 1}}
        from name                    {get {data}}
        from total-prefix-count      {get {data}}
        from active-prefix-count     {get {data}}
        from received-prefix-count   {get {data}}
        from accepted-prefix-count   {get {data}}
        from suppressed-prefix-count {get {data}}
    }
}

set junosParse(%tmplt_bgp-rib%) {
    from bgp-rib {
        foreachkey {
            get {
                {name data -> alias name}
                {total-prefix-count      data -> alias total-prefix-count}
                {active-prefix-count     data -> alias active-prefix-count}
                {received-prefix-count   data -> alias received-prefix-count}
                {accepted-prefix-count   data -> alias accepted-prefix-count}
                {suppressed-prefix-count data -> alias suppressed-prefix-count}
            }
        }
    }    
}

set junosParse(bgp_peer_pre) {
    from bgp-information {
        from bgp-peer {
            key {peer-id -> index {0 1}}
            
            from peer-address {get {data}}
            from peer-as {get {data}}
            from local-address {get {data}}
            from local-as {get {data}}
            from description {get {data}}
            from peer-group {get {data}}
            from peer-cfg-rti {get {data}}
            from peer-fwd-rti {get {data}}
            from peer-type {get {data}}
            from peer-state {get {data}}
            from peer-id {get {data}}
            from local-id {get {data}}
            from nlri-type-peer {get {data}}
            
            %tmplt_bgp-rib_pre%
        }
        from attributes {
            return
        }
    }
}

set junosParse(bgp_peer) {
    transform bgp_peer_pre
    
    from {bgp-information bgp-peer -> alias bgp-peer} {
        foreachkey {
            get {
                {peer-address data -> alias peer-address}
                {peer-as data -> alias peer-as}
                {local-address data -> alias local-address}
                {local-as data -> alias local-as}
                {description data -> alias description}
                {peer-group data -> alias peer-group}
                {peer-cfg-rti data -> alias vrf}
                {peer-fwd-rti data -> alias peer-fwd-rti}
                {peer-type data -> alias peer-type}
                {peer-state data -> alias peer-state}
                {peer-id data -> alias peer-id}
                {nlri-type-peer data -> alias nlri-type-peer}
            }
            
            %tmplt_bgp-rib%
        }
    }
}

dicttr::create_interface junosParse



set junosData {
bgp-information {
    {
        bgp-peer {
            {
                attributes {junos:style detail} 
                peer-address {{data 168.168.1.1+13071}} 
                peer-as {{data 65002}} 
                local-address {{data 168.168.1.20+179}} 
                local-as {{data 65001}} 
                description {{data {### CLIENT_EBGP ###}}} 
                peer-group {{data EBGP-PEER-CLIENT}} 
                peer-cfg-rti {{data INET}} 
                peer-fwd-rti {{data INET}} 
                peer-type {{data External}} 
                peer-state {{data Established}} 
                peer-flags {{data {Sync RSync}}} 
                rsync-flags {{data SocketReplicated}} 
                last-state {{data EstabSync}} 
                last-event {{data RsyncAck}} 
                last-error {{data Cease}} 
                bgp-option-information {
                    {
                        export-policy {{data pol-peer-CLIENT-export}} 
                        import-policy {{data pol-peer-CLIENT-import}} 
                        bgp-options {{data {RemovePrivateAS LogUpDown PeerAS Refresh}}} 
                        bgp-options2 {{}} 
                        bgp-options-extended {{data GracefulShutdownRcv}} 
                        bgp-options-extended2 {{}} 
                        holdtime {{data 90}} 
                        preference {{data 170}} 
                        gshut-recv-local-preference {{data 0}}
                    }
                }
                flap-count {{data 2}} 
                last-flap-event {{data InterfaceAddrDeleted}} 
                last-unreplicate-event {{data {Peer went down}}} 
                recv-ebgp-origin-validation-state {{data Reject}} 
                bgp-error {
                    {
                        name {{data Cease}} 
                        send-count {{data 2}} 
                        receive-count {{data 0}}
                    }
                } 
                peer-id {{data 192.168.30.1}} 
                local-id {{data 10.201.254.1}} 
                active-holdtime {{data 90}} 
                keepalive-interval {{data 30}} 
                group-index {{data 60}} 
                peer-index {{data 0}} 
                snmp-index {{data 160}} 
                bgp-peer-iosession {
                    {
                        iosession-thread-name {{data bgpio-0}} 
                        iosession-state {{data Enabled}}
                    }
                } 
                bgp-bfd {
                    {
                        bfd-configuration-state {{data disabled}} 
                        bfd-operational-state {{data down}}
                    }
                } 
                local-interface-name {{data xe-7/1/16.0}} 
                local-interface-index {{data 1525}} 
                peer-restart-nlri-configured {{data inet-unicast}} 
                nlri-type-peer {{data inet-unicast}} 
                nlri-type-session {{data inet-unicast}} 
                peer-refresh-capability {{data 2}}
                peer-stale-route-time-configured {{data 300}} 
                peer-no-restart {{data null}} 
                peer-restart-nlri-negotiated {{}}
                peer-end-of-rib-received {{data inet-unicast}} 
                peer-end-of-rib-sent {{data inet-unicast}}
                peer-end-of-rib-scheduled {{}}
                peer-no-helper {{data null}} 
                peer-no-llgr-helper {{data null}} 
                peer-4byte-as-capability-advertised {{data 20545}}
                peer-addpath-not-supported {{data null}}
                bgp-rib {
                    {
                        attributes {junos:style detail} 
                        name {{data INET.inet.0}}
                        rib-bit {{data 180001}} 
                        bgp-rib-state {{data {BGP restart is complete}}} 
                        vpn-rib-state {{data {VPN restart is complete}}} 
                        send-state {{data {in sync}}}
                        active-prefix-count {{data 10}} 
                        received-prefix-count {{data 10}} 
                        accepted-prefix-count {{data 10}} 
                        suppressed-prefix-count {{data 0}} 
                        advertised-prefix-count {{data 194}}
                    }
                }
                last-received {{data 13}} 
                last-sent {{data 19}} 
                last-checked {{data 7390919}} 
                input-messages {{data 268719}} 
                input-updates {{data 30}} 
                input-refreshes {{data 0}} 
                input-octets {{data 5106716}} 
                output-messages {{data 253216}} 
                output-updates {{data 494}} 
                output-refreshes {{data 0}} 
                output-octets {{data 4825389}} 
                bgp-output-queue {
                    {
                        number {{data 23}} 
                        count {{data 0}} 
                        table-name {{data INET.inet.0}} 
                        rib-adv-nlri {{data inet-unicast}}
                    }
                }
            }
        }
    }
}    
}



junosParse::bgp_peer $junosData


#Result
set Result {
bgp-peer {
    192.168.30.1 {
        peer-address 168.168.1.1+13071 
        peer-as 65002 
        local-address 168.168.1.20+179 
        local-as 65001 
        description {### CLIENT_EBGP ###} 
        peer-group EBGP-PEER-CLIENT 
        vrf INET 
        peer-fwd-rti INET 
        peer-type External 
        peer-state Established 
        peer-id 192.168.30.1 
        nlri-type-peer inet-unicast 
        bgp-rib {
            INET.inet.0 {
                name INET.inet.0 
                total-prefix-count {} 
                active-prefix-count 10 
                received-prefix-count 10 
                accepted-prefix-count 10 
                suppressed-prefix-count 0
            }
        }
    }
}
}
```
