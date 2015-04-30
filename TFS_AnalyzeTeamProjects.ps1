function Import-TFSAssembly_2010 {
    Add-Type -AssemblyName "Microsoft.TeamFoundation.Client, Version=10.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
    Add-Type -AssemblyName "Microsoft.TeamFoundation.Common, Version=10.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
    Add-Type -AssemblyName "Microsoft.TeamFoundation, Version=10.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
    Add-Type -AssemblyName "Microsoft.TeamFoundation.VersionControl.Client, Version=10.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
    Add-Type -AssemblyName "Microsoft.TeamFoundation.WorkItemTracking.Client, Version=10.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
}

function Import-TFSAssemblies_2013 {
    Add-Type -LiteralPath "C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\ReferenceAssemblies\v2.0\Microsoft.TeamFoundation.Client.dll";
    Add-Type -LiteralPath "C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\ReferenceAssemblies\v2.0\Microsoft.TeamFoundation.Common.dll";
    Add-Type -LiteralPath "C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\ReferenceAssemblies\v2.0\Microsoft.TeamFoundation.dll";
    Add-Type -LiteralPath "C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\ReferenceAssemblies\v2.0\Microsoft.TeamFoundation.VersionControl.Client.dll";
    Add-Type -LiteralPath "C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\ReferenceAssemblies\v2.0\Microsoft.TeamFoundation.WorkItemTracking.Client.dll";
}

function Generate-Hash ($inputString){
        $md5 = [System.Security.Cryptography.MD5]::Create();
        $asciiEncoding = New-Object -TypeName System.Text.ASCIIEncoding;
        $inputBytes = $asciiEncoding.GetBytes($inputString);
        $hash = $md5.ComputeHash($inputBytes);
        $sb = New-Object -TypeName System.Text.StringBuilder;
        foreach($byte in $hash){
            [void]$sb.Append($byte.ToString("x2"));        
        }
        $sb.ToString();
}

function Sort-Children ($parentNode){
    $children = $parentNode.ChildNodes | Sort
    $children | % {$parentNode.RemoveChild($_)} | Out-Null
    $children | % {$parentNode.AppendChild($_)} | Out-Null
    $children | % {Sort-Children($_)} | Out-Null
}

function Remove-Nodes ($nodeToProcess, $xpathExpression){
    $nodesToRemove = $nodeToProcess.SelectNodes($xpathExpression) 
    foreach($node in $nodesToRemove)
    {
        $parentNode = $node.ParentNode
        [void]$parentNode.RemoveChild($node)
        $parentNode.AppendChild($parentNode.OwnerDocument.CreateTextNode("")) | Out-Null
    }
}

function Get-TfsTeamProjectCollectionIds ($configServer) {
    # Get a list of TeamProjectCollections
    [guid[]]$types = [guid][Microsoft.TeamFoundation.Framework.Common.CatalogResourceTypes]::ProjectCollection
    $options = [Microsoft.TeamFoundation.Framework.Common.CatalogQueryOptions]::None
    $configServer.CatalogNode.QueryChildren( $types, $false, $options) | % { $_.Resource.Properties["InstanceId"]}
}

Import-TFSAssembly_2010
#Import-TFSAssembly_2013

Clear-Host

# Do a little Authentication to ensure we can do anything
$configServer = [Microsoft.TeamFoundation.Client.TfsConfigurationServerFactory]::GetConfigurationServer("http://pitfs02:8080/tfs")
[void]$configServer.Authenticate()
if(!$configServer.HasAuthenticated)
{
    Write-Host "Not Authenticated"
    exit
}
else
{
    Write-Host "Authenticated"
    
    $tpcIds = Get-TfsTeamProjectCollectionIds($configServer)

    #dictionary of all fields found on PTCs
    $witFieldDictionary = @{}
    [int]$totalFieldsFound = 6
    
    #iterate through each TPC
    foreach($tpcId in $tpcIds){
        #Get TPC instance
        $tpc = $configServer.GetTeamProjectCollection($tpcId)
        Write-host "----------------- $($tpc.Name) ---------------------------"

        # get list of version control repos
        $vcs = $tpc.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])
        $vspec = [Microsoft.TeamFoundation.VersionControl.Client.VersionSpec]::Latest
        $recursionTypeOne = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]::OneLevel
        $recursionTypeFull = [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]::Full
        $deletedState = [Microsoft.TeamFoundation.VersionControl.Client.DeletedState]::NonDeleted
        $itemType = [Microsoft.TeamFoundation.VersionControl.Client.ItemType]::Any
        $allReposInTPC = $vcs.GetItems("`$/", $vspec, $recursionTypeOne, $deletedState, $itemType, $false).Items

        $wiService = New-Object "Microsoft.TeamFoundation.WorkItemTracking.Client.WorkItemStore" -ArgumentList $tpc
        #Get a list of TeamProjects
        $tps = $wiService.Projects

        #iterate through the TeamProjects
        foreach ($tp in $tps)
        { 
            Write-host "---------------- $($tp.Name) ----------------"
            #most recent changeset check-in for this TP
            $currentTP = $allReposInTPC | ? {$_.ServerItem.Substring(2) -eq $($tp.Name)}
            $newitemSpec = New-Object Microsoft.TeamFoundation.VersionControl.Client.ItemSpec -ArgumentList $currentTP.ServerItem, $recursionTypeFull
            $latestChange = $vcs.GetItems($newitemSpec, $vspec, $deletedState, $itemType, $getItemsOptions).Items | Sort-Object CheckinDate -Desc
            [string]$mostRecentCheckin = $latestChange[0].CheckinDate.ToShortDateString()
            Write-host "Most recent checkin date is $mostRecentCheckin"

            #most recent work item change
            $wiql = "SELECT [System.Id], [Changed Date] FROM WorkItems WHERE [System.TeamProject] = '$($tp.name)' ORDER BY [Changed Date] DESC"
            $wiQuery = New-Object -TypeName "Microsoft.TeamFoundation.WorkItemTracking.Client.Query" -ArgumentList $wiService, $wiql
            $results = $wiQuery.RunQuery()
            [string]$mostRecentChangedWorkItem = ""
            if ($results.Count -gt 0) {
	            $mostRecentChangedWorkItem = $results[0].ChangedDate.ToShortDateString()
            }
            Write-Host "Most recent work item changed date is $mostRecentChangedWorkItem"

            #Get a list of WIT in this TP
            $witList = witadmin listwitd /collection:$($tpc.Name) /p:$($tp.Name) | Sort-Object;
            $stringifiedWITList = [string]::Join("", $witList) -replace " ", "";
            $fieldsFingerprint = Generate-Hash $stringifiedWITList;
            $witList | % { if ($witFieldDictionary.ContainsKey($_) -eq $false) { $witFieldDictionary.Add($_, $totalFieldsFound); $totalFieldsFound += 3; } } | Out-Null
            
            Write-Host "Hash value of all field names is $fieldsFingerprint . (Process Template Id)";
            
            $csvLine = New-Object object[] 100;
            $csvLine[0] = $($tpc.Name); $csvLine[1] = $($tp.Name); $csvLine[2] = $fieldsFingerprint;
            $csvLine[3] = ""; $csvLine[4] = $mostRecentCheckin; $csvLine[5] = $mostRecentChangedWorkItem;
            
            # create folder for Team Project artifacts
            if (!(Test-Path -Path C:\TFS\Results\WIT_EXPORTS\$($tp.Name))){
                $null = New-Item -ItemType directory -Path C:\TFS\Results\WIT_EXPORTS\$($tp.Name)
            }

            $allWITHash = "";
            #iterate through the WIT
            for ($i=0; $i -lt $witList.Length; $i++)
            {
                $wit = $witList[$i]; 
                $witStartCol = $witFieldDictionary[$wit];
                $csvLine[$witStartCol] = $wit
                
                #get number of work items for this WIT
                $wiql = "Select [System.Id] from WorkItems WHERE [System.WorkItemType] = '$wit' AND [System.TeamProject] = '$($tp.Name)'"
                $wiQuery = New-Object -TypeName "Microsoft.TeamFoundation.WorkItemTracking.Client.Query" -ArgumentList $wiService, $wiql
                $csvLine[$witStartCol+1] = $wiQuery.RunQuery().Count
                
                #get xml output
                [xml]$wit_definition_xml = witadmin exportwitd /collection:$($tpc.Name) /p:$($tp.Name) /n:$wit;

                # remove some nodes that cause fingerprinting problems but not a meaningful difference
                Remove-Nodes $wit_definition_xml "//SUGGESTEDVALUES"
                Remove-Nodes $wit_definition_xml "//VALIDUSER"
                Remove-Nodes $wit_definition_xml "//comment()"

                # sort all of the fields by name
                $fields = $wit_definition_xml.WITD.WORKITEMTYPE.FIELDS
                $sortedFields = $fields.FIELD | Sort Name

                # sort all of the fields children
                foreach($field in $sortedFields){
                    Sort-Children $field
                }

                # convert all field elements to non-self closing elemenets
                $sortedFields | % {$_.AppendChild($_.OwnerDocument.CreateTextNode("")) }| Out-Null

                #replace original field nodelist with sorted field node list
                [void]$fields.RemoveAll()
                $sortedFields | foreach { $fields.AppendChild($_) } | Out-Null

                #save a copy of the un-compressed wit for manual comparisons
                #[void]$wit_definition_xml.Save("C:\TFS\Results\WIT_EXPORTS\$($tp.Name)\$($wit)_$($tp.Name).xml")
                
                # http://blogs.technet.com/b/heyscriptingguy/archive/2011/03/21/use-powershell-to-replace-text-in-strings.aspx
                $compressed = $wit_definition_xml.InnerXML -replace " ", "";
                $output = Generate-Hash $compressed
                $allWITHash += $output;
                $csvLine[$witStartCol+2]= $output;
            }
           
            $csvLine[3] =  Generate-Hash $allWITHash
            $csvLine = [string]::Join(",", $csvLine)
            Write-Host $csvLine;
            $csvLine >> "C:\TFS\Results\witd.csv";
        }   
    }
}