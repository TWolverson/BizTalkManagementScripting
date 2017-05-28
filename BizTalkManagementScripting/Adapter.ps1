function RegisterBehaviorExtensions {
    $proxy = Get-HandlerProxy -handlerName "WCF-Custom" -hostInstanceName "Snd_x64" -direction Send
    Get-BehaviorExtensionTypes ([System.Reflection.Assembly]::LoadWithPartialName("System.ServiceModel")) | %{
    
        $proxy.AddBehaviorExtension($_)
    
    }
    $proxy.Save()
}

function Get-BehaviorExtensionTypes{
	param([System.Reflection.Assembly]$assembly)

    Add-Type -AssemblyName System.ServiceModel

	$extensionTypes = $assembly.GetTypes() | ?{ 
        $_.IsSubclassOf([System.ServiceModel.Configuration.BehaviorExtensionElement]) 
    }

    $extensionTypes
}


function Get-HandlerProxy {
    param(
        [string]$handlerName,
        [string]$hostInstanceName,
        [ValidateSet("Receive", "Send")]
        [string]$direction
    )

    $adapter = New-Object -TypeName PSObject -Property @{
        HandlerName = $handlerName
        HostInstanceName = $hostInstanceName
        Direction = $direction
    }

    $adapter | Add-Member -MemberType NoteProperty -Name extensionTypes -Value (New-Object System.Collections.ArrayList)
    
    $adapter | Add-Member -MemberType ScriptMethod -Name AddBehaviorExtension -Value {
        param([Type]$extensionType)
        if($this.extensionTypes -notcontains $extensionType) {
            $this.extensionTypes.Add($extensionType)
        }
    }

    $adapter | Add-Member -MemberType ScriptMethod -Name GetAdapterWmiProxy -Value {
        if($this.Direction = "Receive") {
            $adapterWmi = Get-WmiObject -Class MSBTS_ReceiveHandler -Filter "AdapterName=$($this.adapterName)"
        }
        else {
            $adapterWmi = Get-WmiObject -Class MSBTS_SendHandler2 -Filter "AdapterName=$($this.adapterName)"
        }
        $adapterWmi        
    }

    $adapter | Add-Member -MemberType ScriptMethod -Name Save -Value {

        # Get a WMI instance for the receive or send handler
        $adapterWmi = $this.GetAdapterWmiProxy()
        [xml]$xmlConfiguration = $adapterWmi["CustomCfg"]

        # serialize the types collection to XML
        $this.extensionTypes | %{
            [Type]$extensionType = $_
            $alreadyExists = $xmlConfiguration.SelectSingleNode("//*[type='$($extensionType.AssemblyQualifiedName)']")
            if($alreadyExists -ne $null){
                $xmlConfiguration.ReplaceChild($alreadyExists, $this.SerializeAsXml($extensionType))
            }
            else {
                $xmlConfiguration.AppendChild($this.SerializeAsXml($extensionType))
            }
        }

        # write the XML to the adapter config using WMI
        $adapterWmi["CustomCfg"] = $xmlConfiguration.OuterXml
        $adapterWmi.Put()
    }

    $adapter
}

