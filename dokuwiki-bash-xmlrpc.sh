#!/bin/bash

# Variable for session management
COOKIE_JAR=$(mktemp)

# Function to perform cleanup tasks
cleanup() {
    # Delete the temporary file
    rm "$COOKIE_JAR"
}

# Set the script completion handler
trap cleanup EXIT

# Function to send an XML-RPC request and retrieve the response
send_xml_rpc_request() {
  local url="$1"
  local request="$2"

  # Send the request using curl and capture the response
  local response
  response=$(curl -fsSL -X POST "$url" \
    -H "Content-Type: text/xml" \
    --cookie-jar "$COOKIE_JAR" \
    --cookie "$COOKIE_JAR" \
    --data-binary "$request")

  echo "$response"
}

# Function to convert JSON to XML
convert_json_to_xml() {
  local json="$1"
  local root_element_name="$2"

  # Convert JSON to XML
  local xml
  xml=$(echo "$json" | jq -c -r '
"@"     as $attr_prefix |
"#text" as $content_key |

# ">" only needs to be escaped if preceded by "]]".
# Some whitespace also need escaping, at least in attribute.
{ "&": "&amp;", "<": "&lt;", ">": "&gt;"    } as $escapes      |
{ "&": "&amp;", "<": "&lt;", "\"": "&quot;" } as $attr_escapes |

def text_to_xml:          split( "" ) | map( $escapes[.]       // . ) | join( "" );
def text_to_xml_attr_val: split( "" ) | map( $attr_escapes [.] // . ) | join( "" );

def node_to_xml:
   if type == "string" then
      text_to_xml
   else
      (
         if .attrs then
            .attrs |
            to_entries |
            map( " " + .key + "=\"" + ( .value | text_to_xml_attr_val ) + "\"" ) |
            join( "" )
         else
            ""
         end
      ) as $attrs |

      if .children and ( .children | length ) > 0 then
         ( .children | map( node_to_xml ) | join( "" ) ) as $children |
         "<" + .name + $attrs + ">" + $children + "</" + .name + ">"
      else
         "<" + .name + $attrs + "/>"
      end
   end
;

def fix_tree( $name ):
   type as $type |
   if $type == "array" then
      .[] | fix_tree( $name )
   elif $type == "object" then
      reduce to_entries[] as { key: $k, value: $v } (
         { name: $name, attrs: {}, children: [] };

         if $k[0:1] == $attr_prefix then
            .attrs[ $k[1:] ] = $v
         elif $k == $content_key then
            .children += [ $v ]
         else
            .children += [ $v | fix_tree( $k ) ]
         end
      )
   else
      { name: $name, attrs: {}, children: [ . ] }
   end
;

def fix_tree: fix_tree( "" ) | .children[];

fix_tree | node_to_xml')

  echo "<$root_element_name>$xml</$root_element_name>"
}

# Function to convert XML to JSON using jq
convert_xml_to_json() {
  local xml_content="$1"

  # Convert XML to JSON using jq

  # Remove XML version header using tail command
  local xml_content_without_header=$(echo "$xml_content" | tail -n +2)

  # Convert XML to JSON using xq
  local json=$(echo "$xml_content_without_header" | xq)

  echo "$json"
}

# prepares and sends the request to the server
send_request() {
    local method_name="$1"
    local options="$2"

    # Convert JSON options to XML
    local xml_options=$(convert_json_to_xml "$options" "params")

    # Construct XML-RPC request
    local request="<?xml version=\"1.0\"?><methodCall><methodName>$method_name</methodName>$xml_options</methodCall>"

    local response=$(send_xml_rpc_request "$url" "$request")

    # Convert XML response to JSON
    local json_response=$(convert_xml_to_json "$response")

    echo "$json_response"
}

# dokuwiki_login() function
#
# This function performs a login request to a DokuWiki XML-RPC server using the provided username and password.
# It constructs a JSON request with the username and password, sends it using the send_request() function,
# and extracts the boolean value from the response using jq.
#
# Arguments:
#   - user: The username to authenticate with.
#   - password: The password associated with the provided username.
#
# Returns:
#   - The boolean value indicating the success of the login operation.
#     - 1: If the login is successful.
#     - 0: If the login fails.
#
# Example usage:
#   result=$(dokuwiki_login "myusername" "mypassword")
#
dokuwiki_login() {
    local user="$1"
    local password="$2"

    local request=$(printf '
    {
        "param" : [
            { "value" : { "string" : "%s" } },
            { "value" : { "string" : "%s" } }
        ]
    }' "$user" "$password")

    echo $(send_request "dokuwiki.login" "$request" | jq -r '.methodResponse.params.param.value.boolean')
}

# dokuwiki_pageList() function
#
# This function retrieves a list of pages from a DokuWiki XML-RPC server based on the specified parameters.
# It sends the request using the `send_request()` function and extracts the page list from the response using `jq`.
#
# Arguments:
#   - namespace: The namespace or page ID to retrieve the page list from.
#   - pattern (optional): A pattern to filter the page list. Default: empty string.
#   - depth (optional): The depth of sub-pages to include in the page list. Default: 0 (all sub-pages).
#
# Returns:
#   - The page list extracted from the response as an array of page names.
#
# Example usage:
#   pages=$(dokuwiki_pageList "namespace" "pattern" 2 | jq -r '.[].struct.member[] | select(.name == "id") | .value.string')
#
dokuwiki_pageList() {
    local namespace="$1"
    local pattern="${2:-}"
    local depth="${3:-0}"

    # depth = 0 -> all sub pages
    local request=$(printf '
    {
        "param" : [
            { "value" : { "string" : "%s" } },
            { "value" : { "struct" : {
                "member" : [
                    {
                        "name": "pattern",
                        "value": { "string" : "%s" }
                    },
                    {
                        "name": "depth",
                        "value": { "int" : "%s" }
                    }
                ]
            } } }
        ]
    }' "$namespace" "$pattern" "$depth")

    echo $(send_request "dokuwiki.getPagelist" "$request" | jq -r '.methodResponse.params.param.value.array.data.value' )
}

# dokuwiki_getAllPages() function
#
# This function retrieves a list of all pages from a DokuWiki XML-RPC server.
# It sends the request using the `send_request()` function and extracts the page list from the response using `jq`.
#
# Returns:
#   - The page list extracted from the response as an array of page names.
#
# Example usage:
#   pages=$(dokuwiki_getAllPages | jq -r '.[].struct.member[] | select(.name == "id") | .value.string')
#
dokuwiki_getAllPages() {
    echo $(send_request "wiki.getAllPages" "" | jq -r '.methodResponse.params.param.value.array.data.value' )
}

# dokuwiki_getPage() function
#
# This function retrieves the content of a DokuWiki page using the provided page name.
# It constructs a JSON request using the page name and sends it to the server using the send_request() function.
# The response is parsed using jq to extract the content of the page.
#
# Arguments:
#   - page: The name of the DokuWiki page to retrieve.
#
# Returns:
#   - The content of the specified DokuWiki page as a string.
#
# Example usage:
#   content=$(dokuwiki_getPage "MyPage")
#
dokuwiki_getPage() {
    local page="$1"

   local request=$(printf '
    {
        "param" : [
            { "value" : { "string" : "%s" } }
        ]
    }' "$page")

    echo $(send_request "wiki.getPage" "$request" | jq -r '.methodResponse.params.param.value.string' )
}

# _dokuwiki_updatePage() function
#
# This function is an internal function used to update a DokuWiki page based on the provided parameters.
#
# Arguments:
#   - whatToDo: The type of update to perform, such as "dokuwiki.appendPage" or "wiki.putPage".
#   - page: The name of the page to update.
#   - text: The content of the page to update. (Optional, default: "")
#   - summary: The summary or description of the update. (Optional, default: "")
#   - minor: A flag indicating whether the update should be considered as a minor change. (Optional, default: 0)
#
# Returns:
#   - The boolean value indicating the success of the update operation.
#
_dokuwiki_updatePage() {
    local whatToDo="$1"
    local page="$2"
    local text="${3:-}"
    local summary="${4:-}"
    local minor="${5:-0}"

    # depth = 0 -> all sub pages
    local request=$(printf '
    {
        "param" : [
            { "value" : { "string" : "%s" } },
            { "value" : { "string" : "%s" } },
            { "value" : { "struct" : {
                "member" : [
                    {
                        "name": "summary",
                        "value": { "string" : "%s" }
                    },
                    {
                        "name": "minor",
                        "value": { "bool" : "%s" }
                    }
                ]
            } } }
        ]
    }' "$page" "$text" "$summary", "$minor")

    echo $(send_request "$whatToDo" "$request" | jq -r '.methodResponse.params.param.value.boolean' )
}

# dokuwiki_appendPage() function
#
# This function appends content to a DokuWiki page by calling the internal _dokuwiki_updatePage() function
# with the "dokuwiki.appendPage" as the update type.
#
# Arguments:
#   - Same as _dokuwiki_updatePage() function.
#
# Returns:
#   - The boolean value indicating the success of the update operation.
#
dokuwiki_appendPage() {
   _dokuwiki_updatePage "dokuwiki.appendPage" $@
}

# dokuwiki_putPage() function
#
# This function updates a DokuWiki page by calling the internal _dokuwiki_updatePage() function
# with the "wiki.putPage" as the update type.
#
# Arguments:
#   - Same as _dokuwiki_updatePage() function.
#
# Returns:
#   - The boolean value indicating the success of the update operation.
#
dokuwiki_putPage() {
   _dokuwiki_updatePage "wiki.putPage" $@
}
