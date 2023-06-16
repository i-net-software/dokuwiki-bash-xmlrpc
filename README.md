# Bash XML-RPC Client

This Bash script provides a simple XML-RPC client for interacting with a DokuWiki XML-RPC server. It includes functions to perform various operations such as login, retrieving page lists, retrieving page content, and updating pages.

## Prerequisites

- Bash shell
- cURL
- jq
- xq - see https://github.com/kislyuk/yq

## Usage

1. Clone the repository:

   ```shell
   git clone https://github.com/i-net-software/dokuwiki-bash-xmlrpc.git
   ```

2. Change directory to the repository:

   ```shell
   cd dokuwiki-bash-xmlrpc
   ```

3. Make the script executable:

   ```shell
   chmod +x dokuwiki-bash-xmlrpc.sh
   ```

4. Modify the script to provide the necessary configuration:

   - Set the `url` variable to the URL of your DokuWiki XML-RPC server.
   - If required, install any missing dependencies (cURL, jq, xq).

5. Run the script:

   ```shell
   ./dokuwiki-bash-xmlrpc.sh
   ```

## Available Functions

### dokuwiki_login

This function performs a login request to a DokuWiki XML-RPC server using the provided username and password. It returns a boolean value indicating the success of the login operation.

```shell
dokuwiki_login <username> <password>
```

Example usage:

```shell
result=$(dokuwiki_login "myusername" "mypassword")
```

### dokuwiki_pageList

This function retrieves a list of pages from a DokuWiki XML-RPC server based on the specified parameters. It returns the page list as an array of page names.

```shell
dokuwiki_pageList <namespace> [<pattern>] [<depth>]
```

- `namespace`: The namespace or page ID to retrieve the page list from.
- `pattern` (optional): A pattern to filter the page list. Default: empty string.
- `depth` (optional): The depth of sub-pages to include in the page list. Default: 0 (all sub-pages).

Example usage:

```shell
pages=$(dokuwiki_pageList "namespace" "pattern" 2 | jq -r '.[].struct.member[] | select(.name == "id") | .value.string')
```

### dokuwiki_getAllPages

This function retrieves a list of all pages from a DokuWiki XML-RPC server. It returns the page list as an array of page names.

```shell
dokuwiki_getAllPages
```

Example usage:

```shell
pages=$(dokuwiki_getAllPages | jq -r '.[].struct.member[] | select(.name == "id") | .value.string')
```

### dokuwiki_getPage

This function retrieves the content of a DokuWiki page using the provided page name. It returns the content of the specified DokuWiki page as a string.

```shell
dokuwiki_getPage <page>
```

- `page`: The name of the DokuWiki page to retrieve.

Example usage:

```shell
content=$(dokuwiki_getPage "MyPage")
```

### dokuwiki_appendPage

This function appends content to a DokuWiki page. It returns a boolean value indicating the success of the update operation.

```shell
dokuwiki_appendPage <page> [<text>] [<summary>] [<minor>]
```

- `page`: The name of the page to update.
- `text` (optional): The content of the page to update. Default: empty string.
- `summary` (optional): The summary or description of the update. Default: empty string.
- `minor` (optional): A flag indicating whether the update should be considered as a minor