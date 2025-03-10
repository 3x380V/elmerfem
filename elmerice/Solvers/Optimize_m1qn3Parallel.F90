!/*****************************************************************************/
! *
! *  Elmer/Ice, a glaciological add-on to Elmer
! *  http://elmerice.elmerfem.org
! *
! * 
! *  This program is free software; you can redistribute it and/or
! *  modify it under the terms of the GNU General Public License
! *  as published by the Free Software Foundation; either version 2
! *  of the License, or (at your option) any later version.
! * 
! *  This program is distributed in the hope that it will be useful,
! *  but WITHOUT ANY WARRANTY; without even the implied warranty of
! *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! *  GNU General Public License for more details.
! *
! *  You should have received a copy of the GNU General Public License
! *  along with this program (in file fem/GPL-2); if not, write to the 
! *  Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, 
! *  Boston, MA 02110-1301, USA.
! *
! *****************************************************************************/
! ******************************************************************************
! *
! *  Authors: 
! *  Email:   
! *  Web:     http://elmerice.elmerfem.org
! *
! *  Original Date: 
! * 
! *****************************************************************************
!  Optimize a cost function 
!    using quasi-Newton M1QN3 Routine in Reverse Communication
!    Using Euclidean inner product
!
!   2D/3D
!
!  Need:
!  - Value of the Cost function
!  - Value of the variable to optimize
!  - Value of gradient of cost function with respect to Variable
!      (sum the contribution of each partition shared node)
!  - Optimisation Mask Variable (Optional): name of a mask variable. If
!  mask.lt.0 the variable is considered fixed
!
! => Update the new value of variable to optimize
!
! *****************************************************************************
SUBROUTINE Optimize_m1qn3Parallel_init( Model,Solver,dt,TransientSimulation )
!------------------------------------------------------------------------------
  USE DefUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t), TARGET :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  INTEGER :: NormInd, LineInd, i
  LOGICAL :: GotIt, MarkFailed, AvoidFailed
  CHARACTER(LEN=MAX_NAME_LEN) :: Name

  Name = ListGetString( Solver % Values, 'Equation',GotIt)
  IF( .NOT. ListCheckPresent( Solver % Values,'Variable') ) THEN
      CALL ListAddString( Solver % Values,'Variable',&
          '-nooutput -global '//TRIM(Name)//'_var')
 END IF
END
!******************************************************************************

SUBROUTINE Optimize_m1qn3Parallel( Model,Solver,dt,TransientSimulation )
!------------------------------------------------------------------------------
!******************************************************************************
  USE DefUtils
  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model

  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!  
  CHARACTER(LEN=MAX_NAME_LEN) :: SolverName
  TYPE(Element_t),POINTER ::  Element
! Variables Beta,DJDbeta and Cost  
  TYPE(ValueList_t), POINTER :: SolverParams
  TYPE(Variable_t), POINTER :: BetaVar,CostVar,GradVar,MaskVar,TimeVar,BWeightVar
  REAL(KIND=dp), POINTER :: BetaValues(:),CostValues(:),GradValues(:),MaskValues(:)
  INTEGER, POINTER :: BetaPerm(:),GradPerm(:),NodeIndexes(:),MaskPerm(:),BWeightPerm(:)
  INTEGER, SAVE :: VarDOFs

  REAL(KIND=dp),allocatable :: x(:),g(:),b(:),xx(:),gg(:),bb(:),xtot(:),gtot(:),btot(:)
  REAL(KIND=dp) :: f,Normg,Change
  REAL(KIND=dp),SAVE :: Oldf=0._dp 
  real :: dumy

  integer :: i,j,t,n,NMAX,NActiveNodes,NPoints,ni,ind
  INTEGER :: status(MPI_STATUS_SIZE)
  integer,allocatable :: ActiveNodes(:),NodePerPe(:)
  integer,allocatable :: NewNode(:)
  integer, allocatable :: LocalToGlobalPerm(:),nodePerm(:),TestPerm(:)

  logical :: FirstVisit=.TRUE.,Firsttime=.TRUE.,Found,UseMask,ComputeNormG=.FALSE.,&
       UnFoundFatal=.TRUE.,MeshIndep, BoundarySolver
  logical,SAVE :: Parallel
  logical,allocatable :: VisitedNode(:)

  CHARACTER(LEN=MAX_NAME_LEN) :: CostSolName,VarSolName,GradSolName,NormM1QN3,&
       MaskVarName, NormFile
  CHARACTER*10 :: date,temps


!Variables for m1qn3
  external simul_rc !,euclid,ctonbe,ctcabe
  character*3 normtype
  REAL(KIND=dp) :: dxmin,df1,epsrel
  real(kind=dp), allocatable :: dz(:),dzs(:)
  REAL :: rzs(1)
  integer :: imp,io=20,imode(3),omode=-1,niter,nsim,iz(5),ndz,reverse,indic,izs(1)
  integer :: ierr,Npes,ntot
  CHARACTER(LEN=MAX_NAME_LEN) :: IOM1QN3
  logical :: DISbool
!
  save NActiveNodes,Npes,NPoints,ntot
   
  save x,g,b,xx,gg,bb,xtot,gtot,btot
  save ActiveNodes,NodePerPe

  save TestPerm, BWeightPerm, BWeightVar

  save normtype,dxmin,df1,epsrel,dz,dzs,rzs,imp,io,imode,omode,niter,nsim,iz,ndz,reverse,indic,izs
  save SolverName, SolverParams
  SAVE FirstVisit,Firsttime,MeshIndep,BoundarySolver
  save ComputeNormG,NormFile
  save CostSolName,VarSolName,GradSolName,IOM1QN3

  INTERFACE
     SUBROUTINE MeshUnweight(n,x,y,ps,izs,rzs,dzs)
       !------------------------------------------------------------------------------
       INTEGER n,izs(*)
       REAL rzs(*)
       DOUBLE PRECISION x(n),y(n),ps,dzs(*)
     END SUBROUTINE MeshUnweight

     SUBROUTINE MeshUnweight_ctonb(n,u,v,izs,rzs,dzs)
       !------------------------------------------------------------------------------
       INTEGER n,izs(*)
       REAL rzs(*)
       DOUBLE PRECISION u(n),v(n),dzs(*)
     END SUBROUTINE MeshUnweight_ctonb

     SUBROUTINE MeshUnweight_ctcab(n,u,v,izs,rzs,dzs)
       !------------------------------------------------------------------------------
       INTEGER n,izs(*)
       REAL rzs(*)
       DOUBLE PRECISION u(n),v(n),dzs(*)
     END SUBROUTINE MeshUnweight_ctcab

     SUBROUTINE euclid (n,x,y,ps,izs,rzs,dzs)
       !------------------------------------------------------------------------------
       INTEGER n,izs(*)
       REAL rzs(*)
       DOUBLE PRECISION x(n),y(n),ps,dzs(*)
     END SUBROUTINE euclid
            
     SUBROUTINE ctonbe (n,u,v,izs,rzs,dzs)
       !------------------------------------------------------------------------------
       INTEGER n,izs(*)
       REAL rzs(*)
       DOUBLE PRECISION u(n),v(n),dzs(*)
     END SUBROUTINE ctonbe

     SUBROUTINE ctcabe (n,u,v,izs,rzs,dzs)
       !------------------------------------------------------------------------------               
       INTEGER n,izs(*)
       REAL rzs(*)
       DOUBLE PRECISION u(n),v(n),dzs(*)
     END SUBROUTINE ctcabe

  END INTERFACE
  PROCEDURE (MeshUnweight), POINTER :: prosca => NULL()
  PROCEDURE (MeshUnweight_ctonb), POINTER :: ctonb => NULL(),ctcab => NULL()

!  Read Constant from sif solver section
      IF(FirstVisit) Then
            FirstVisit=.FALSE.
            CALL DATE_AND_TIME(date,temps)
            WRITE(SolverName, '(A)') 'Optimize_m1qn3Parallel'

       ! Check we have a parallel run
          Parallel=(ParEnv % PEs > 1)
       !!!!!

            SolverParams => GetSolverParams()

            CostSolName =  GetString( SolverParams,'Cost Variable Name', Found)
                IF(.NOT.Found) THEN
                    CALL WARN(SolverName,'Keyword >Cost Variable Name< not found  in section >Solver<')
                    CALL WARN(SolverName,'Taking default value >CostValue<')
                    WRITE(CostSolName,'(A)') 'CostValue'
                END IF
            VarSolName =  GetString( SolverParams,'Optimized Variable Name', Found)
                IF(.NOT.Found) THEN
                    CALL WARN(SolverName,'Keyword >Optimized Variable Name< not found  in section >Solver<')
                    CALL WARN(SolverName,'Taking default value >Beta<')
                    WRITE(VarSolName,'(A)') 'Beta'
                END IF
            GradSolName =  GetString( SolverParams,'Gradient Variable Name', Found)
                IF(.NOT.Found) THEN
                    CALL WARN(SolverName,'Keyword >Gradient Variable Name< not found  in section >Solver<')
                    CALL WARN(SolverName,'Taking default value >DJDB<')
                    WRITE(GradSolName,'(A)') 'DJDB'
                END IF

          MaskVarName = GetString( SolverParams,'Optimisation Mask Variable',UseMask)
            IF (UseMask) Then
                MaskVar => VariableGet( Model % Mesh % Variables, MaskVarName,UnFoundFatal=UnFoundFatal) 
                MaskValues => MaskVar % Values 
                MaskPerm => MaskVar % Perm 
            ENDIF

            MeshIndep=ListGetLogical(SolverParams,"Mesh Independent", Found)
            IF(.NOT.Found) THEN
              CALL WARN(SolverName,'Keyword >Mesh Independent< not found in solver params')
              CALL WARN(SolverName,'Taking default value >FALSE<')
              MeshIndep=.FALSE.
            END IF

            BoundarySolver = ( Solver % ActiveElements(1) > Model % Mesh % NumberOfBulkElements )
            IF(BoundarySolver) THEN
              CALL Info(SolverName, "Solver defined on boundary", Level=10)
            ELSE
              CALL Info(SolverName, "Solver defined on body", Level=10)
            END IF

           If (ParEnv % MyPe.EQ.0) then
              NormFile=GetString( SolverParams,'gradient Norm File',Found)
              IF(Found)  Then
                    ComputeNormG=.True.
                    open(io,file=trim(NormFile))
                    write(io,'(a1,a2,a1,a2,a1,a4,5x,a2,a1,a2,a1,a2)')'#',date(5:6),'/',date(7:8),'/',date(1:4), &
                                 temps(1:2),':',temps(3:4),':',temps(5:6)
                    close(io)
              END IF

!!  initialization of m1qn3 variables
            dxmin=GetConstReal( SolverParams,'M1QN3 dxmin', Found)
                IF(.NOT.Found) THEN
                    CALL WARN(SolverName,'Keyword >M1QN3 dxmin< not found  in section >Solver<')
                    CALL WARN(SolverName,'Taking default value >1.e-10<')
                    dxmin=1.e-10
                END IF
            epsrel=GetConstReal( SolverParams,'M1QN3 epsg', Found)
                IF(.NOT.Found) THEN
                    CALL WARN(SolverName,'Keyword >M1QN3 epsg< not found  in section >Solver<')
                    CALL WARN(SolverName,'Taking default value >1.e-06<')
                    epsrel=1.e-6
                END IF
            niter=GetInteger(SolverParams,'M1QN3 niter', Found)
                IF(.NOT.Found) THEN
                    CALL WARN(SolverName,'Keyword >M1QN3 niter< not found  in section >Solver<')
                    CALL WARN(SolverName,'Taking default value >200<')
                    niter=200
                END IF
            nsim=GetInteger(SolverParams,'M1QN3 nsim', Found)
                IF(.NOT.Found) THEN
                    CALL WARN(SolverName,'Keyword >M1QN3 nsim< not found  in section >Solver<')
                    CALL WARN(SolverName,'Taking default value >200<')
                    nsim=200
                END IF
            imp=GetInteger(SolverParams,'M1QN3 impres', Found)
                IF(.NOT.Found) THEN
                    CALL WARN(SolverName,'Keyword >M1QN3 impres< not found  in section >Solver<')
                    CALL WARN(SolverName,'Taking default value >5<')
                    imp=5
                END IF
            DISbool=GetLogical( SolverParams, 'M1QN3 DIS Mode', Found)
                IF(.NOT.Found) THEN
                    CALL WARN(SolverName,'Keyword >M1QN3 DIS Mode< not found  in section >Solver<')
                    CALL WARN(SolverName,'Taking default value >FALSE<')
                    DISbool=.False.
                END IF
                if(DISbool) then
                    imode(1)=0 !DIS Mode
                else
                    imode(1)=1 !SIS Mode
                End if
            df1=GetConstReal( SolverParams,'M1QN3 df1', Found)
                IF(.NOT.Found) THEN
                   CALL WARN(SolverName,'Keyword >M1QN3 df1< not found  in section >Solver<')
                   CALL WARN(SolverName,'Taking default value >0.2<')
                   df1=0.2
                End if
                CostVar => VariableGet( Model % Mesh % Variables, CostSolName,UnFoundFatal=UnFoundFatal)
                CostValues => CostVar % Values
                df1=CostValues(1)*df1
             NormM1QN3 = GetString( SolverParams,'M1QN3 normtype', Found)
                 IF((.NOT.Found).AND.((NormM1QN3(1:3).ne.'dfn').OR.(NormM1QN3(1:3).ne.'sup') &
                     .OR.(NormM1QN3(1:3).ne.'two'))) THEN
                       CALL WARN(SolverName,'Keyword >M1QN3 normtype< not good in section >Solver<')
                       CALL WARN(SolverName,'Taking default value >dfn<')
                       !PRINT *,'M1QN3 normtype  ',NormM1QN3(1:3)
                       normtype = 'dfn'
                  ELSE
                       !PRINT *,'M1QN3 normtype  ',NormM1QN3(1:3)
                       normtype = NormM1QN3(1:3)
                  END IF

              IF(normtype(1:3) /= 'dfn' .AND. MeshIndep) THEN
                CALL Fatal(SolverName,"Selected 'Mesh Independent = Logical True' &
                     &but M1QN3 normtype is not 'dfn'!")
              END IF

              IOM1QN3 = GetString( SolverParams,'M1QN3 OutputFile', Found)
                 IF(.NOT.Found) THEN
                       CALL WARN(SolverName,'Keyword >M1QN3 OutputFile< not found  in section >Solver<')
                       CALL WARN(SolverName,'Taking default value >M1QN3.out<')
                       WRITE(IOM1QN3,'(A)') 'M1QN3.out'
                 END IF
                 open(io,file=trim(IOM1QN3))
                    write(io,*) '******** M1QN3 Output file ************'
                    write(io,'(a2,a1,a2,a1,a4,5x,a2,a1,a2,a1,a2)') date(5:6),'/',date(7:8),'/',date(1:4), &
                                 temps(1:2),':',temps(3:4),':',temps(5:6)
                    write(io,*) '*****************************************'
                 close(io)
              ndz=GetInteger( SolverParams,'M1QN3 ndz', Found)
                  IF(.NOT.Found) THEN
                       CALL WARN(SolverName,'Keyword >M1QN3 ndz< not found  in section >Solver<')
                       CALL WARN(SolverName,'Taking default value >5< update')
                       ndz=5
                   END IF

                   IF(.NOT.MeshIndep) THEN
                     ALLOCATE(dzs(1))
                     dzs=0.0
                   END IF
                    imode(2)=0 
                    imode(3)=0 
                    reverse=1 
                    omode=-1 
                    rzs=0.0
                    izs=0

            End if !ParEnv % MyPe=0

        End if ! FirtsVisit


! Omode from previous iter; if > 0 m1qn3 has terminated => return 
     IF (omode.gt.0) then 
             WRITE(Message,'(a,I1)') 'm1qn3 finished; omode=',omode 
             CALL Info(SolverName, Message, Level=1) 
             return  
     End if

!  Get Variables CostValue, Beta and DJDBeta
    CostVar => VariableGet( Model % Mesh % Variables, CostSolName,UnFoundFatal=UnFoundFatal)
    CostValues => CostVar % Values 
    f=CostValues(1)

     BetaVar => VariableGet( Model % Mesh % Variables, VarSolName,UnFoundFatal=UnFoundFatal) 
     BetaValues => BetaVar % Values 
     BetaPerm => BetaVar % Perm 
     VarDOFs = BetaVar % DOFs

     GradVar => VariableGet( Model % Mesh % Variables, GradSolName,UnFoundFatal=UnFoundFatal) 
     GradValues   => GradVar % Values 
     GradPerm => GradVar % Perm 
     IF (GradVar % DOFs.NE.VarDOFs) THEN
         CALL FATAL(SolverName,'Optimisation and gradient variables have different DOFs')
     END IF

     IF(MeshIndep) THEN
       IF(FirstTime) THEN
         ALLOCATE(BWeightPerm(SIZE(BetaPerm)))
         BWeightPerm = BetaPerm
       END IF

       !Compute the boundary weights of basal nodes
       !This could be done just once, assuming the mesh never changes.
       CALL CalculateNodalWeights(Solver, BoundarySolver, BWeightPerm, Var=BWeightVar)
     END IF

! Do some allocation etc if first iteration
  If (Firsttime) then 
          
     Firsttime = .False.

     NMAX=Model % Mesh % NumberOfNodes
     allocate(VisitedNode(NMAX),NewNode(NMAX))

!!!!!!!!!!!!find active nodes 
      VisitedNode=.false.  
      NewNode=-1

      NActiveNodes=0 
      DO t=1,Solver % NumberOfActiveElements
         Element => GetActiveElement(t)
         n = GetElementNOFNodes()
         NodeIndexes => Element % NodeIndexes
         Do i=1,n
           if (VisitedNode(NodeIndexes(i))) then
                   cycle
           else
              VisitedNode(NodeIndexes(i))=.true.
              IF (UseMask) Then
                       IF (MaskValues(MaskPerm(NodeIndexes(i))).lt.0) cycle
              END IF
              NActiveNodes=NActiveNodes+1
              NewNode(NActiveNodes)=NodeIndexes(i)
           endif
        End do
      End do

     if (NActiveNodes.eq.0) THEN
            WRITE(Message,'(A)') 'NActiveNodes = 0 !!!'
            CALL FATAL(SolverName,Message)
     End if
  
    allocate(ActiveNodes(NActiveNodes),LocalToGlobalPerm(NActiveNodes),x(VarDOFs*NActiveNodes),g(VarDOFs*NActiveNodes))
    IF(MeshIndep) ALLOCATE(b(VarDOFs*NActiveNodes))
    ActiveNodes(1:NActiveNodes)=NewNode(1:NActiveNodes)

    deallocate(VisitedNode,NewNode)

!! Gather number of active nodes in each partition and compute total number of
!active nodes in partition 0
    Npes=ParEnv % PEs
    allocate(NodePerPe(Npes))

    IF (Parallel) THEN
      call MPI_Gather(NActiveNodes,1,MPI_Integer,NodePerPe,1,MPI_Integer,0,ELMER_COMM_WORLD,ierr)
    ELSE
      NodePerPe(1)=NActiveNodes
    END IF

    if (ParEnv % MyPE.eq.0) then
          ntot=0
          Do i=1,Npes
               ntot=ntot+NodePerPe(i)
          End do
          allocate(xtot(VarDOFs*ntot),gtot(VarDOFs*ntot))
          IF(MeshIndep) ALLOCATE(btot(VarDOFs*ntot))
          allocate(NodePerm(ntot))
    End if

! Send global node  numbering to partition 0
    IF (Parallel) THEN
      LocalToGlobalPerm(1:NActiveNodes)=Model % Mesh % ParallelInfo % GlobalDOFs(ActiveNodes(1:NActiveNodes))
    Else
      LocalToGlobalPerm(1:NActiveNodes)=ActiveNodes(1:NActiveNodes)
    End if



   if (ParEnv % MyPE .ne.0) then
             call MPI_SEND(LocalToGlobalPerm(1),NActiveNodes,MPI_INTEGER,0,8001,ELMER_COMM_WORLD,ierr)
   else
           NodePerm(1:NActiveNodes)=LocalToGlobalPerm(1:NActiveNodes)
           ni=1+NActiveNodes
           Do i=2,Npes
             call   MPI_RECV(NodePerm(ni),NodePerPe(i),MPI_INTEGER,i-1,8001,ELMER_COMM_WORLD, status, ierr )
             ni=ni+NodePerPe(i)
           End do

! Create a permutation table from NodePerm
           allocate(TestPerm(ntot))
           ind=1
           TestPerm(1)=ind
           Do i=2,ntot
              Do j=1,i-1
                 if (NodePerm(j).eq.NodePerm(i)) exit
               End do
               if (j.eq.i) then
                       ind=ind+1
                       TestPerm(i)=ind
               else
                       TestPerm(i)=TestPerm(j)
               end if
           End do

           NPoints=ind
           allocate(xx(VarDOFs*Npoints),gg(VarDOFs*Npoints),bb(VarDOFs*NPoints))
           deallocate(NodePerm,LocalToGlobalPerm)

 ! M1QN3 allocation of dz function of Npoints nd requested number of updates
           IF (DISbool) then
                   ndz=4*VarDOFs*NPoints+ndz*(2*VarDOFs*NPoints+1)+10
           else
                   ndz=3*VarDOFs*NPoints+ndz*(2*VarDOFs*NPoints+1)+10
           end if
           allocate(dz(ndz))

           IF(MeshIndep) THEN
             ALLOCATE(dzs(VarDOFs*Npoints))
             dzs=0.0
           END IF
    End if
   
  END IF

  Do i=1,NActiveNodes
     IF (BetaPerm(ActiveNodes(i))==0) CALL FATAL(SolverName,'Optimized Variable is not defined on this node')
     IF (GradPerm(ActiveNodes(i))==0) CALL FATAL(SolverName,'Gradient Variable is not defined on this node')
     Do j=1,VarDOFs
          x(VarDOFs*(i-1)+j)=BetaValues(VarDOFs*(BetaPerm(ActiveNodes(i))-1)+j)
          g(VarDOFs*(i-1)+j)=GradValues(VarDOFs*(GradPerm(ActiveNodes(i))-1)+j)
          IF(MeshIndep) b(VarDOFs*(i-1)+j)=BWeightVar % Values(&
             BWeightVar % Perm(ActiveNodes(i)))
     End DO
  End Do

    ! Send variables to partition 0
    ! and receive results from partition 0

     if (ParEnv % MyPE .ne.0) then

                     call MPI_SEND(x(1),VarDOFs*NActiveNodes,MPI_DOUBLE_PRECISION,0,8003,ELMER_COMM_WORLD,ierr)
                     call MPI_SEND(g(1),VarDOFs*NActiveNodes,MPI_DOUBLE_PRECISION,0,8004,ELMER_COMM_WORLD,ierr)
                     IF(MeshIndep) call MPI_SEND(b(1),VarDOFs*NActiveNodes,&
                          MPI_DOUBLE_PRECISION,0,8006,ELMER_COMM_WORLD,ierr)

                     call MPI_RECV(x(1),VarDOFs*NActiveNodes,MPI_DOUBLE_PRECISION,0,8005,ELMER_COMM_WORLD,status, ierr )
                     call MPI_RECV(omode,1,MPI_Integer,0,8006,ELMER_COMM_WORLD,status,ierr )

                     ! Update Beta Values 
                     Do i=1,NActiveNodes
                        Do j=1,VarDOFs
                            BetaValues(VarDOFs*(BetaPerm(ActiveNodes(i))-1)+j)=x(VarDOFs*(i-1)+j)
                        End DO
                     End Do
     else
                     xtot(1:VarDOFs*NActiveNodes)=x(1:VarDOFs*NActiveNodes)
                     gtot(1:VarDOFs*NActiveNodes)=g(1:VarDOFs*NActiveNodes)
                     IF(MeshIndep) btot(1:VarDOFs*NActiveNodes)=b(1:VarDOFs*NActiveNodes)
                     ni=1+VarDOFs*NActiveNodes
                     Do i=2,Npes
                       call MPI_RECV(xtot(ni),VarDOFs*NodePerPe(i),MPI_DOUBLE_PRECISION,i-1,8003,ELMER_COMM_WORLD, status, ierr )
                       call MPI_RECV(gtot(ni),VarDOFs*NodePerPe(i),MPI_DOUBLE_PRECISION,i-1,8004,ELMER_COMM_WORLD, status, ierr )
                       IF(MeshIndep) call MPI_RECV(btot(ni),VarDOFs*NodePerPe(i),MPI_DOUBLE_PRECISION,&
                            i-1,8006,ELMER_COMM_WORLD, status, ierr )
                       ni=ni+VarDOFs*NodePerPe(i)
                     End do

                     xx=0.0
                     gg=0.0
                     IF(MeshIndep) bb=0.0
                     Do i=1,ntot
                       Do j=1,VarDOFs
                         xx(VarDOFs*(TestPerm(i)-1)+j)=xtot(VarDOFs*(i-1)+j)  ! same Beta Value for same node
                         gg(VarDOFs*(TestPerm(i)-1)+j)=gg(VarDOFs*(TestPerm(i)-1)+j)+gtot(VarDOFs*(i-1)+j)  ! gather the contribution to DJDB 
                         IF(MeshIndep) &
                          bb(VarDOFs*(TestPerm(i)-1)+j)=bb(VarDOFs*(TestPerm(i)-1)+j)+btot(VarDOFs*(i-1)+j)! gather boundary weights
                        End Do
                     End do 

                     IF(MeshIndep) THEN
                       dzs = bb
                       gg = gg / bb
                     END IF

                     If (ComputeNormG) then
                             TimeVar => VariableGet( Model % Mesh % Variables, 'Time' )
                             Normg=0.0_dp

                             Do i=1,VarDOFs*NPoints
                                Normg=Normg+gg(i)*gg(i)
                             End do
                             open(io,file=trim(NormFile),position='append')
                              write(io,'(e13.5,2x,e15.8)') TimeVar % Values(1),sqrt(Normg)
                             close(io)
                    End if

            IF(MeshIndep) THEN
              prosca => MeshUnweight
              ctonb => MeshUnweight_ctonb
              ctcab => MeshUnweight_ctcab
            ELSE
              prosca => Euclid
              ctonb => ctonbe
              ctcab => ctcabe
            END IF

            Oldf=sqrt(SUM(xx(:)*xx(:))/(1.0d0*NPoints))
            ! go to minimization
            open(io,file=trim(IOM1QN3),position='append')
            call m1qn3 (simul_rc,prosca,ctonb,ctcab,VarDOFs*NPoints,xx,f,gg,dxmin,df1, &
                        epsrel,normtype,imp,io,imode,omode,niter,nsim,iz, &
                        dz,ndz,reverse,indic,izs,rzs,dzs)

            close(io)
            WRITE(Message,'(a,e15.8,x,I2)') 'm1qn3: Cost,omode= ',f,omode
            CALL Info(SolverName, Message, Level=3)

            f=sqrt(SUM(xx(:)*xx(:))/(1.0d0*NPoints))
            Solver%Variable%Values(1)=f
            Solver%Variable%Norm=f
            IF (SIZE(Solver%Variable % Values) == Solver%Variable % DOFs) THEN
             !! MIMIC COMPUTE CHANGE STYLE
             Change=2.*(f-Oldf)/(f+Oldf)
             Change=abs(Change)
             WRITE( Message, '(a,g15.8,g15.8,a)') &
              'SS (ITER=1) (NRM,RELC): (',f, Change,&
              ' ) :: Optimize'
             CALL Info( 'ComputeChange', Message, Level=3 )
             Oldf=f
            ENDIF

            ! Put new Beta Value in xtot and send to each partition
            xtot=0.0
            Do i=1,ntot
              Do j=1,VarDOFs
               xtot(VarDOFs*(i-1)+j)=xx(VarDOFs*(TestPerm(i)-1)+j)
              End Do
            End do

            ! Update Beta Values 
            Do i=1,NActiveNodes
                 Do j=1,VarDOFs
                      BetaValues(VarDOFs*(BetaPerm(ActiveNodes(i))-1)+j)=xtot(VarDOFs*(i-1)+j)
                 End DO
            End Do
                      
            ni=1+VarDOFs*NActiveNodes
            Do i=2,Npes
                  call MPI_SEND(xtot(ni),VarDOFs*NodePerPe(i),MPI_DOUBLE_PRECISION,i-1,8005,ELMER_COMM_WORLD,ierr)
                  call MPI_SEND(omode,1,MPI_Integer,i-1,8006,ELMER_COMM_WORLD,ierr)
                  ni=ni+VarDOFs*NodePerPe(i)
            End do

  endif

   Return
!------------------------------------------------------------------------------
END SUBROUTINE Optimize_m1qn3Parallel
!------------------------------------------------------------------------------

!Replacement for prosca to precondition gradient by dividing by boundary weights
!Uses REAL dp array 'dzs' passed from Optimize_... => m1qn3.F => MeshUnweight.
SUBROUTINE MeshUnweight (n,x,y,ps,izs,rzs,dzs)

  IMPLICIT NONE
  INTEGER n,izs(*)
  REAL rzs(*)
  DOUBLE PRECISION x(n),y(n),ps,dzs(*)

  INTEGER i

  ps=0.d0
  DO i=1,n
    ps=ps+x(i)*y(i)*dzs(i)
  ENDDO

  RETURN
END SUBROUTINE MeshUnweight


SUBROUTINE MeshUnweight_ctonb (n,u,v,izs,rzs,dzs)

  IMPLICIT NONE
  INTEGER n,izs(*)
  REAL rzs(*)
  DOUBLE PRECISION u(n),v(n),dzs(*)

  INTEGER i

  DO i=1,n
    v(i)=u(i)*SQRT(dzs(i))
  END DO
  RETURN

END SUBROUTINE MeshUnweight_ctonb

SUBROUTINE MeshUnweight_ctcab (n,u,v,izs,rzs,dzs)
  
  IMPLICIT NONE
  INTEGER n,izs(*)
  REAL rzs(*)
  DOUBLE PRECISION u(n),v(n),dzs(*)

  INTEGER i

  DO i=1,n
    v(i)=u(i)/SQRT(dzs(i))
  ENDDO
  RETURN

END SUBROUTINE MeshUnweight_ctcab
