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
