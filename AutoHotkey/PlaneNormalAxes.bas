'------------------------------------------------------------------------------
' Creates three reference axes, each normal to one of the default planes
' (Front, Top, Right) and passing through the origin:
'
'   Front Axis = normal to Front Plane (global Z) = Top  Plane x Right Plane
'   Top Axis   = normal to Top Plane   (global Y) = Front Plane x Right Plane
'   Right Axis = normal to Right Plane (global X) = Front Plane x Top Plane
'
' Planes are located by feature order (first three RefPlane features in the
' tree), so it works with renamed or localized plane names.
'------------------------------------------------------------------------------
Option Explicit

Dim swApp As SldWorks.SldWorks

Sub main()
    Set swApp = Application.SldWorks

    Dim swModel As SldWorks.ModelDoc2
    Set swModel = swApp.ActiveDoc
    If swModel Is Nothing Then
        MsgBox "Open a part or assembly first.", vbExclamation
        Exit Sub
    End If
    If swModel.GetType = swDocDRAWING Then
        MsgBox "This macro works in parts and assemblies only.", vbExclamation
        Exit Sub
    End If

    ' Collect Front, Top, Right (first three reference planes in the tree)
    Dim planes(0 To 2) As SldWorks.Feature
    Dim count As Long
    Dim swFeat As SldWorks.Feature
    Set swFeat = swModel.FirstFeature
    Do While Not swFeat Is Nothing And count < 3
        If swFeat.GetTypeName2 = "RefPlane" Then
            Set planes(count) = swFeat
            count = count + 1
        End If
        Set swFeat = swFeat.GetNextFeature
    Loop
    If count < 3 Then
        MsgBox "Could not find the Front, Top and Right planes.", vbExclamation
        Exit Sub
    End If

    ' Order in tree: 0 = Front, 1 = Top, 2 = Right
    ' Axis normal to a plane = intersection of the other two planes
    MakeAxis swModel, planes(1), planes(2), "Front Axis"
    MakeAxis swModel, planes(0), planes(2), "Top Axis"
    MakeAxis swModel, planes(0), planes(1), "Right Axis"

    swModel.ClearSelection2 True
    swModel.GraphicsRedraw2
End Sub

Private Sub MakeAxis(swModel As SldWorks.ModelDoc2, planeA As SldWorks.Feature, _
                     planeB As SldWorks.Feature, axisName As String)
    Dim ok As Boolean

    swModel.ClearSelection2 True
    ' Select by name through the Extension (more reliable than Feature.Select2)
    ' (The True/False return values are unreliable here, so verify by
    ' counting what is actually selected instead.)
    swModel.Extension.SelectByID2 planeA.Name, "PLANE", 0, 0, 0, False, 0, Nothing, 0
    swModel.Extension.SelectByID2 planeB.Name, "PLANE", 0, 0, 0, True, 0, Nothing, 0
    If swModel.SelectionManager.GetSelectedObjectCount2(-1) <> 2 Then
        MsgBox "Could not select planes for " & axisName & vbCrLf & _
               "Selected count = " & swModel.SelectionManager.GetSelectedObjectCount2(-1), _
               vbExclamation
        Exit Sub
    End If

    ' Two selected planes -> axis at their intersection
    swModel.InsertAxis2 True
    swModel.ClearSelection2 True

    ' Rename the newest feature if it is the axis we just made
    Dim swNew As SldWorks.Feature
    Set swNew = swModel.FeatureByPositionReverse(0)
    If Not swNew Is Nothing Then
        If swNew.GetTypeName2 = "RefAxis" Then swNew.Name = axisName
    End If
End Sub
