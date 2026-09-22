DefinitionBlock ("", "SSDT", 2, "L5Pro", "NvidiaOf", 0x00001000)
{
    External (_SB_.PCI0.GPP0.PEGP, DeviceObj)
    External (_SB_.PCI0.GPP0.PEGP._PS3, MethodObj)    // 0 Arguments
    External (_SB_.PCI0.GPP0.PEGP.OPCE, IntObj)

    Scope (\_SB.PCI0.GPP0.PEGP)
    {
        Method (_INI, 0, NotSerialized)  // _INI: Initialize
        {
            \_SB.PCI0.GPP0.PEGP.OPCE = 0x03
            _PS3 ()
        }
    }
}
