param(
    [Parameter(Mandatory=$true)]
    [string]$Secret,
    
    [string]$Destination = (Get-Location),
    [bool]$GenerateDebugFiles = $true
)

Install-Module -Name powershell-yaml -Repository PSGallery -Scope CurrentUser -Force


function Write-ToFile
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $Path,
        
        [Parameter(Mandatory=$true)]
        [string] $Content
    )

    
    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
    [System.IO.File]::WriteAllLines($Path, $Content, $Utf8NoBomEncoding)
}


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

function ExtractSelect
{
    param
    (
        [psobject]$obj
    )
    return $obj.select.name;
}

function ExtractMultiSelect
{
    param
    (
        [psobject]$obj
    )

    foreach($o in $obj.multi_select)
    {
        $o.name;
    }
}
function ExtractUrl
{
    param
    (
        [psobject]$obj
    )
    
    return $obj.url;
}

function ExtractDateTimeFromString
{
    param
    (
        [psobject]$String
    )
   
    $date = [System.DateTimeOffset]::MinValue
    if([System.DateTimeOffset]::TryParseExact("$String +0800", 'MM/dd/yyyy H:mm:ss K', [System.Globalization.CultureInfo]:: InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$date))
    {
        return $date
    }
<#
if([DateTime]::TryParseExact($String, 'MM/dd/yyyy H:mm:ss', [System.Globalization.CultureInfo]:: InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$date))
    {
        return $date
    }
#>

    return $null
}

function ExtractDate
{
    param
    (
        [psobject]$obj
    )
    return ExtractDateTimeFromString -String $obj.date.start
}

function ExtractField
{
    param 
    (
        [psobject]$obj
    )
    if(-not $obj)
    {
        return $null
    }

    $typeName = $obj.'type'

    
    if(-not $typeName)
    {
        return $null
    }
    switch($typeName.Trim())
    {
        'text' {
            ExtractText -obj $obj
        }
        'title' {
            ExtractTitle -obj $obj
        }
        'url' {
            ExtractUrl -obj $obj
        }
        'date' {
            ExtractDate -obj $obj
        }
        'select' {
            ExtractSelect -obj $obj
        }
        'multi_select' {
            ExtractMultiSelect -obj $obj
        }
        'rich_text' {
            ExtractRichText -obj $obj
        }
    }
}

function ExtractTitle
{
    param
    (
        [psobject]$obj
    )
 
    foreach($o in $obj.title)
    {
        ExtractField -obj $o
    }

}

function ExtractText
{
    param
    (
        [psobject]$obj
    )

    if($obj.text.link)
    {
        "[$($obj.text.content)]($(ExtractUrl -obj $obj.text.link))"
    }
    else
    {
        $obj.text.content
    }
    
}

function ExtractRichText
{
    param
    (
        [psobject]$obj
    )

    foreach($o in $obj.rich_text)
    {
        ExtractText($o)
    }
}



# Require variables
$IndexDateFormat = 'yyyy-MM-dd'
# post dates
$HashPostsByDate = @{};


# Prep Debug folder
$DebugLocation = Join-Path $Destination 'debug'
if(-not (Test-Path $DebugLocation))
{
    New-Item -ItemType Directory -Path $DebugLocation
}
Else
{
    Get-ChildItem -Path $DebugLocation -File | Remove-Item
}

# Prep _post folder
$PostsLocation = (Join-Path $Destination '_posts')
if(Test-Path $PostsLocation)
{
    Get-ChildItem -Path $PostsLocation -File | Remove-Item
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

    # Service call
    $queryResponse = Invoke-RestMethod -Uri "https://api.notion.com/v1/search" -Body $BodyInJson -Headers $headers -Method Post   
    

    
    # set variable for next iteration
    $hasMore = $queryResponse.has_more
    $startCursor = $queryResponse.next_cursor;



    $obj = $queryResponse.results[0];   

    "======================================================="    


    $knownObj = @{
        object = $obj.object;
        id = $obj.id;
        notion_url = $obj.url;
        created_time = ExtractDateTimeFromString -String $obj.created_time;
        last_edited_time = ExtractDateTimeFromString -String $obj.last_edited_time;
        parent_type = $obj.parent.type;
        parent_database_id = $obj.parent.database_id;
        archived = $obj.archived;
        title = (ExtractField -obj $obj.properties.Name) -join ''
        hosts = ExtractField -obj $obj.properties.Hosts
    }

    $fieldNames = $obj.properties | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

    foreach($name in $fieldNames)
    {        
        $value = $obj.properties.$name;

        if($name -match 'date')
        {
            $name = 'talktime'
        }

        $knownObj[(($name -replace '\W', '_').ToLowerInvariant())] = (ExtractField -obj $value) 
    }

        

    
    $indexDate = $null

    if($knownObj.talktime)
    {
        $indexDate = $knownObj.talktime.ToString($IndexDateFormat)
        $fileName = ("$($indexDate)-$($knownObj.title)-$($knownObj.id)" -replace '\W', '-') + ".md"
        $path = (Join-Path $PostsLocation $fileName);

        # add this reponse to debug folder
        Add-Content (Join-Path $DebugLocation "$fileName.yaml") -Value ($obj | ConvertTo-Yaml)
        $postIndexDate = $knownObj.talktime.ToString($IndexDateFormat)
        if($HashPostsByDate.ContainsKey($postIndexDate) -and -not $HashPostsByDate[$postIndexDate].Contains($fileName))
        {
            $HashPostsByDate[$postIndexDate] += $fileName;        
        }
        else
        {
            $HashPostsByDate[$postIndexDate] = @($fileName)
        }
    }
    else
    {
        # invalide event date, nothing to do.
        continue
    }

    $path
    

    $tags = @('Talk')

    if($knownObj.talktime)
    {
        $tags += $knownObj.talktime.ToString($IndexDateFormat)
    }

    if($knownObj.hosts)
    {
        $tags += $knownObj.hosts
    }

    $knownObj["tags"] = $tags;
    $knownObj["indexDate"] = $indexDate

    $yaml = $knownObj | ConvertTo-Yaml

    # Service call
    $blockResponse = Invoke-RestMethod -Uri "https://api.notion.com/v1/blocks/$($obj.id)/children" -Headers $headers -Method Get 
    
    

    Add-Content (Join-Path $DebugLocation "$fileName.yaml") -Value ($blockResponse | ConvertTo-Yaml)

    $content = ""
    foreach($block in $blockResponse.results)
    {
        $content += (ExpandBlock -Block $block) + "`n"
    }
    


    # write to md
    Write-ToFile -Path $path -Content "---`n$yaml---`n$properties`n$content"

    
}


"----------------- Post Data ----------------------"
$postIndexByDateLocation = Join-Path (Join-Path $Destination '_data') 'PostsIndexedByDate.yaml'
$postIndexByDateLocation
Write-ToFile -Path $postIndexByDateLocation -Content ($HashPostsByDate | ConvertTo-Yaml)



# Build Calendar
$TotalWeeks = 4
$now = [DateTime]::Today
$dayOfWeekValue = $now.DayOfWeek.value__
$travel = $dayOfWeekValue - 1
if($dayOfWeekValue -eq 0)
{
    $travel = 6
}
$monday = $now.Subtract([TimeSpan]::FromDays($travel))

$CalendarHash = @{
}


$day = $monday
$DaysInAWeek = 7
$week = 1
while($week -le $TotalWeeks)
{
    $d = 1
    $collection = @()
    while($d -le $DaysInAWeek)
    {
        $dayName = $day.ToString($IndexDateFormat)
        $title = if( $day.Day -eq 1  -or $day -eq $monday) {$day.ToString("d MMM") } ELSE { $day.Day }
        $collection += @{
            index = $dayName
            title = $title
            posts = $HashPostsByDate[$dayName]
        }
        
        $day = $day.Add([TimeSpan]::FromDays(1));
        ++$d
    }
    
    $CalendarHash["Week$week"]= $collection
    ++$week
}




"----------------- Cal Data ----------------------"
$calDataLocation = Join-Path (Join-Path $Destination '_data') 'TalkCalendar.yaml'
$calDataLocation
Write-ToFile -Path $calDataLocation -Content ($CalendarHash.GetEnumerator() | Sort-Object -Property name | ConvertTo-Yaml)
