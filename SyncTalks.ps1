param(
    [Parameter(Mandatory=$true)]
    [string]$Secret,
    
    [Parameter(Mandatory=$true)]
    [string]$Destination
)

Install-Module -Name powershell-yaml -Force -Repository PSGallery -Scope CurrentUser


function BuildListItem
{
    param (
        [string]$header, 
        [psobject] $block, 
        [int]$depth
    )
    $indent = 3 * $depth
    $index = 0
    $str = ""
    while ($index -lt 3)
    {
        $str += " ";
        ++$index;
    }
    if($block.bulleted_list_item.text)
    {
        $str = $str + $header + " "
    }
    foreach($t in $block.bulleted_list_item.text)
    {
        $str = $str + $t.plain_text;
    }    
    $str
    foreach($c in $bloc.bulleted_list_item.children)
    {
        BuildListItem -header $header -block $c -depth ++$depth
    }
}

function ExpandText
{
    param(
    [psobject[]] $texts
    )

    foreach($t in $texts)
    {
        if($t.href)
        {
            "[$($t.plain_text)]($($t.href))"
        }
        else
        {
            $t.plain_text
        }
    }
}


function ExpandBlock
{
    param(
    [psobject] $block
    )
    
    
    if($block.type -eq 'paragraph')
    {
        foreach($p in $block.paragraph)
        {
            ExpandText($p.text)
        }
    }
    if($block.type -eq 'heading_1')
    {
        "# $($block.heading_1.text.plain_text)"
    }

    if($block.type -eq 'heading_2')
    {
        "## $($block.heading_2.text.plain_text)"
    }

    if($block.type -eq 'heading_3')
    {
        "### $($block.heading_3.text.plain_text)"
    }

        
        

    if($block.type -eq 'bulleted_list_item')
    {
        BuildListItem -header '-' -block $block -depth 1
            
    }

    if($block.type -eq 'numbered_list_item')
    {
        BuildListItem -header '1.' -block $block -depth 1            
    }
        
    

    if($block.type -eq 'to_do')
    {
        $str = "";
        if($block.to_do.checked)
        {
            $str = "✅" 
        }
        else
        {
            $str = "⬜"
        }
        $str = $str + ' '

        ExpandText($block.to_do.text)
    }

        

    if($block.type -eq 'toggle')
    {
        foreach ($t in $block.toggle.text)
        {
            "⛛ $($t.plain_text)"
        }
    }

    if($block.type -eq 'child_page')
    {
        "📄 $($block.child_page.title)"
    }

    if($block.has_children)
    {
        foreach($c in $block.children)
        {
            ExpandBlock -block $c
        }
    }
}





$headers = @{
    "Notion-Version"= "2021-05-13";
    "Authorization" = "Bearer $Secret";
    "Content-Type" = "application/json"
}



#Invoke-RestMethod -Uri "https://api.notion.com/v1/databases/" -Headers $headers -Method Get | Set-Variable listOfDatabases

$hasMore = $true;
$pageSize = 1;
$startCursor = $null;
 


while($hasMore)
{
    $body = @{
        page_size = $pageSize;
    } 

    if($startCursor)
    {
        $body["start_cursor"] = $startCursor;
    }



    $BodyInJson = ($body | ConvertTo-Json -Depth 10)
    $queryResponse = Invoke-RestMethod -Uri "https://api.notion.com/v1/search" -Body $BodyInJson -Headers $headers -Method Post   
    
    $obj = $queryResponse.results[0];



    $dateTimeForat = 'yyyy-MM-dd hh:mm tt'

    $obj.created_time = [Datetime]::Parse($obj.created_time, [System.Globalization.CultureInfo]::CurrentCulture).ToString($dateTimeForat)   
    $obj.last_edited_time = [Datetime]::Parse($obj.last_edited_time, [System.Globalization.CultureInfo]::CurrentCulture).ToString($dateTimeForat)   
    
    if($obj.properties.Date.date.start)
    {
        $obj.properties.Date.date.start = [Datetime]::Parse($obj.properties.Date.date.start, [System.Globalization.CultureInfo]::CurrentCulture).ToString($dateTimeForat)
    }
    if($obj.properties.Date.date.end)
    {
        $obj.properties.Date.date.end = [Datetime]::Parse($obj.properties.Date.date.end, [System.Globalization.CultureInfo]::CurrentCulture).ToString($dateTimeForat)
    }
    

    "======================================================="
    $fileName = "$([DateTimeOffset]::Parse($obj.created_time).ToString('yyyy-MM-dd'))-$($obj.id)-$($obj.properties.Name.title[0].plain_text)" -replace '\W', '-'
    $path = (Join-Path $Destination "$fileName.md");
    $yaml = ($obj | ConvertTo-Yaml) 
    $yaml = $yaml -replace "Sign up here:", 'Sign_up_here:' 
    $yaml = $yaml -replace 'Meeting Link:', 'Meeting_Link:'
    $path



    

    $blockResponse = Invoke-RestMethod -Uri "https://api.notion.com/v1/blocks/$($obj.id)/children" -Headers $headers -Method Get   

    $content = ""
    foreach($block in $blockResponse.results)
    {
        $content += (ExpandBlock -Block $block) + "`n"
    }
    


    # write to md
    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
    [System.IO.File]::WriteAllLines($path, "---`n$yaml---`n$content", $Utf8NoBomEncoding)

    # set variable for next iteration
    $hasMore = $queryResponse.has_more
    $startCursor = $queryResponse.next_cursor;
    
}

