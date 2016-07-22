<#*****Readme****#

Скрипт предназначен для переноса и развертывания рабочих процессов списков SharePoint2013.

Для использования скрипта необходимо получить файл workflow.xaml, содержащий описание рабочего процесса.
Это можно сделать с помощью функции ExtractWorkflowXaml. Параметры функции:
$url - URL узла, ассоциированный с сервисом Workflow, на котором развернут рабочий процесс;
$wf_displayname - имя рабочего процесса;
$workflow_xaml_path - путь к файлу для сохранения.

Для развертывания рабочего процесса необходимо вызвать функцию DeployListWorkflow. Параметры функции:
$workflow_xaml - путь к файлу;
$url - URL узла, ассоциированный с сервисом Workflow, на которой необходимо развернуть рабочий процесс;
$list_name - имя списка, с которым должен быть ассоциирован рабочий процесс;
$wf_displayname - имя рабочего процесса;
$overwrite - признак необходимости перезаписи рабочего процесса, если он уже существует.
#****************#>

if ((Get-PSSnapin "Microsoft.SharePoint.PowerShell" -ErrorAction SilentlyContinue) -eq $null) 
{
    Add-PSSnapin "Microsoft.SharePoint.PowerShell"
    Write-Host "Added Snapin for SharePoint" -ForegroundColor Yellow
}

function DeployListWorkflow($workflow_xaml, $url, $list_name, $wf_displayname, $overwrite){
    $w = Get-SPWeb $url
    Write-Host "Get web for" $url -ForegroundColor Green

    $wfm = New-Object Microsoft.SharePoint.WorkflowServices.WorkflowServicesManager($w)
    Write-Host "Workflow Service Manager was found:" ($wfm -ne $null) -ForegroundColor @("Red", "Green")[$wfm -ne $null]

    $wfd = $wfm.GetWorkflowDeploymentService()
    Write-Host "Workflow Deployment service discovered:" ($wfd -ne $null) -ForegroundColor @("Red", "Green")[$wfd -ne $null]

    #Check if workflow exists
    $publishedWorkflows = $wfd.EnumerateDefinitions($false)

    $wfdef = $publishedWorkflows | Where-Object {$_.DisplayName -eq $wf_displayname} | Select-Object -First 1
    $wf_exists = $wfdef -ne $null

    if ($wf_exists -and -not $overwrite){
        Write-Host "This workflow already exists. Please set other workflow name or set `$overwrite = `$true." -ForegroundColor Red
    }
    else
    {
        # Publishing workflow
        if ($wfdef -eq $null){
            $wfdef = New-Object Microsoft.SharePoint.WorkflowServices.WorkflowDefinition
        } else {
            Write-Host "Workflow definition will be overwritten." -ForegroundColor Yellow
        }

        $wf_targetlist = $w.Lists[$list_name]

        $wfdef.DisplayName = $wf_displayname
        $wfdef.Xaml = Get-Content $workflow_xaml -Encoding UTF8
        $wfdef.Properties["Overriide"] = $true
        # additional properties for view binding list in SPD #
        if ($wf_targetlist -ne $null){
            $wfdef.SetProperty("RestrictToType", "List")
            $wfdef.SetProperty("RestrictToScope", $wf_targetlist.ID.ToString().ToUpper())
        }
        #***********************#

        $wf_id = $wfd.SaveDefinition($wfdef)
        Write-Host "Workflow definition id:" $wf_id
        $wfd.PublishDefinition($wf_id)

        # Binding to list
        if ($wf_targetlist -eq $null){
            Write-Host ("List <{0}> not found. Binding failed." -f $list_name) -ForegroundColor Red
        }
        else {
            $wfs = $wfm.GetWorkflowSubscriptionService()
            Write-Host "Workflow Subscription service discovered:" ($wfs -ne $null) -ForegroundColor @("Red", "Green")[$wfs -ne $null]
            $wf_subs = $wfs.EnumerateSubscriptions() | Where-Object {$_.DefinitionId -eq $wf_id -and $_.EventSourceId -eq $wf_targetlist.ID}
            # Delete previous subscriptions
            $wf_subs | ForEach-Object {$wfs.DeleteSubscription($_.Id)}
            $wf_tasklist = $w.Lists | Where-Object {$_.Title -eq "Задачи рабочего процесса"} | Select-Object -First 1
            Write-Host "Workflow task list found:" ($wf_tasklist -ne $null) -ForegroundColor @("Red", "Green")[$wf_tasklist -ne $null]

            $wf_histlist = $w.Lists | Where-Object {$_.Title -eq "Журнал рабочего процесса"} | Select-Object -First 1
            Write-Host "Workflow history list found:" ($wf_histlist -ne $null) -ForegroundColor @("Red", "Green")[$wf_histlist -ne $null]

            $wfsub = New-Object Microsoft.SharePoint.WorkflowServices.WorkflowSubscription
            $wfsub.DefinitionId = $wf_id
            $wfsub.Name = $wf_displayname
            $wfsub.Enabled = $true
            $eventTypes = New-Object System.Collections.Generic.List[String]
            $eventTypes.Add("WorkflowStart")
            $wfsub.EventTypes = $eventTypes
            $wfsub.EventSourceId = $wf_targetlist.ID.ToString()
            $wfsub.SetProperty("TaskListId", $wf_tasklist.ID.ToString())
            $wfsub.SetProperty("HistoryListId", $wf_histlist.ID.ToString())
            $wfsub.SetProperty("ListId", $wf_targetlist.ID.ToString())
            $wfsub.SetProperty("Microsoft.SharePoint.ActivationProperties.ListId", $wf_targetlist.ID.ToString())
            # additional properties #
            $wfsub.SetProperty("SharePointWorkflowContext.ActivationProperties.SiteId", $w.Site.ID.ToString())
            $wfsub.SetProperty("SharePointWorkflowContext.ActivationProperties.WebId", $w.ID.ToString())
            #***********************#
            $wfsub_id = $wfs.PublishSubscriptionForList($wfsub, $wf_targetlist.ID)
            Write-Host "Workflow subscription id:" $wfsub_id
        }

        Write-Host "Finished." -ForegroundColor Green
    }
}

function ExtractWorkflowXaml($url, $wf_displayname, $workflow_xaml_path){
    $w = Get-SPWeb $url -ErrorAction SilentlyContinue
    if ($w -eq $null){
        Write-Host "Get web for" $url "failed" -ForegroundColor Red
        return
    }
    Write-Host "Get web for" $url -ForegroundColor Green

    $wfm = New-Object Microsoft.SharePoint.WorkflowServices.WorkflowServicesManager($w) -ErrorAction SilentlyContinue
    Write-Host "Workflow Service Manager was found:" ($wfm -ne $null) -ForegroundColor @("Red", "Green")[$wfm -ne $null]
    if ($wfm -eq $null) { return }

    $wfd = $wfm.GetWorkflowDeploymentService()
    Write-Host "Workflow Deployment service discovered:" ($wfd -ne $null) -ForegroundColor @("Red", "Green")[$wfd -ne $null]
    if ($wfd -eq $null) { return }

    $wf_def = $wfd.EnumerateDefinitions($false) | Where-Object { $_.DisplayName -eq $wf_displayname } | Select-Object -First 1
    Write-Host "Workflow definition was found:" ($wf_def -ne $null) -ForegroundColor @("Red", "Green")[$wf_def -ne $null]
    if ($wf_def -ne $null){
        try {
        $wf_def.Xaml | Out-File $workflow_xaml_path -ErrorVariable ProcessError
        }
        catch{ }
        Write-Host "Export workflow.xaml has been" @("failed", "successfully completed")[$ProcessError.Count -eq 0] -ForegroundColor @("Red", "Green")[$ProcessError.Count -eq 0]
    }
}


#ExtractWorkflowXaml "http://mysp.com/source" "Test workflow" "C:\spmetadata\workflow.xaml"
#DeployListWorkflow "C:\spmetadata\workflow.xaml" "http://mysp.com/sandbox" "Test Workflow List" "My New Workflow" $true