    !!! Generalized BAO module added by J. Dossett
    ! Copied structure from mpk.f90 and Reid BAO code
    !
    ! When using WiggleZ data set cite Blake et al. arXiv:1108.2635

    !for SDSS data set: http://www.sdss3.org/science/boss_publications.php

    ! For rescaling method see Hamann et al, http://arxiv.org/abs/1003.3999

    !AL/JH Oct 2012: encorporate DR9 data into something close to new cosmomc format
    !Dec 2013: merged in DR11 patch (Antonio J. Cuesta, for the BOSS collaboration)

    module bao_Andreu
    use MatrixUtils
    use settings
    use CosmologyTypes
    use CosmoTheory
    use Calculator_Cosmology
    use Likelihood_Cosmology
    use IniObjects
    implicit none

    private

    type, extends(TCosmoCalcLikelihood) :: BAO_Andreu_Likelihood
        !    type, extends(TCosmoCalcLikelihood) :: BAOLikelihood
        integer :: num_bao ! total number of points used
        integer :: type_bao
        !what type of bao data is used
        !1: old sdss, no longer
        !2: A(z) =2 ie WiggleZ
        !3 D_V/rs in fitting forumla appox (DR9)
        !4: D_v - 6DF
        !5: D_A/rs (DR8)
        real(mcp), allocatable, dimension(:) :: bao_z, bao_obs, bao_err
        real(mcp), allocatable, dimension(:,:) :: bao_invcov
    contains
    procedure :: LogLike => BAO_LnLike
    procedure :: ReadIni => BAO_ReadIni
    procedure, private :: SDSS_dvtors
    procedure, private :: SDSS_dAtors
    procedure, private :: Acoustic
    procedure, private :: BAO_DR7_loglike
    procedure, private :: BAO_DR11_loglike
    end type BAO_Andreu_Likelihood

!JAV
    integer,parameter :: DR11_alpha_npoints=41
    integer,parameter :: DR11_alpha_npoints2=31
    real(mcp), dimension (DR11_alpha_npoints) :: DR11_alpha_plel_file
    real(mcp), dimension (DR11_alpha_npoints2) :: DR11_alpha_perp_file
    real(mcp), dimension (DR11_alpha_npoints2,DR11_alpha_npoints) ::   DR11_prob_file
    real(mcp) DR11_dalpha_perp, DR11_dalpha_plel
    real(mcp), dimension (10000) :: DR7_alpha_file, DR7_prob_file
    real(mcp) DR7_dalpha
    real rsdrag_theory
    real(mcp) :: BAO_fixed_rs = -1._mcp
    integer DR7_alpha_npoints

    public BAO_Andreu_Likelihood, BAO_Andreu_Likelihood_Add
    contains

    subroutine BAO_Andreu_Likelihood_Add(LikeList, Ini)
    class(TLikelihoodList) :: LikeList
    class(TSettingIni) :: ini
    Type(BAO_Andreu_Likelihood), pointer :: this
    integer numbaosets, i

    if (Ini%Read_Logical('use_BAO_Andreu',.false.)) then
        numbaosets = Ini%Read_Int('bao_Andreu_numdatasets',0)
        if (numbaosets<1) call MpiStop('Use_BAO_Andreu but numbaosets = 0')
        if (Ini%Haskey('BAO_fixed_rs')) then
            BAO_fixed_rs= Ini%Read_Double('BAO_fixed_rs',-1._mcp)
        end if
        do i= 1, numbaosets
            allocate(this)
            call this%ReadDatasetFile(Ini%ReadFileName(numcat('bao_Andreu_dataset',i)))
            this%LikelihoodType = 'BAO_Andreu'
            this%needs_background_functions = .true.
            call LikeList%Add(this)
        end do
        if (Feedback>1) write(*,*) 'read BAO_Andreu data sets'
    end if

    end subroutine BAO_Andreu_Likelihood_Add

    subroutine BAO_ReadIni(this, Ini)
    class(BAO_Andreu_Likelihood) this
    class(TSettingIni) :: Ini
    character(LEN=:), allocatable :: bao_measurements_file, bao_invcov_file
    integer i,iopb
    Type(TTextFile) :: F

    if (Feedback > 0) write (*,*) 'reading BAO_Andreu data set: '//trim(this%name)
    !if (Feedback > 0) write (*,*) 'reading BAO_Andreu data set:'//trim(this%prob) 
    this%num_bao = Ini%Read_Int('num_bao_Andreu',0)
    if (this%num_bao.eq.0) write(*,*) ' ERROR: parameter num_bao not set'
    this%type_bao = Ini%Read_Int('type_bao_Andreu',1)
    if(this%type_bao /= 3 .and. this%type_bao /=2 .and. this%type_bao /=4 .and. this%type_bao /=5) then
        write(*,*) this%type_bao
        write(*,*)'ERROR: Invalid bao type specified in BAO_Andreu dataset: '//trim(this%name)
        call MPIStop()
    end if

    allocate(this%bao_z(this%num_bao))
    this%bao_z(1)=2.36d0

    !allocate(this%bao_obs(this%num_bao))
    !allocate(this%bao_err(this%num_bao))

    !bao_measurements_file = Ini%ReadFileName('bao_measurements_file')
    !call F%Open(bao_measurements_file)
    !do i=1,this%num_bao
    !    read (F%unit,*, iostat=iopb) this%bao_z(i),this%bao_obs(i),this%bao_err(i)
    !end do
    !call F%Close()

    !if (this%name == 'DR7') then
    !    !don't used observed value, probabilty distribution instead
    !    call BAO_DR7_init(Ini%ReadFileName('prob_dist'))
    !elseif (this%name == 'DR11CMASS') then
    !    !don't used observed value, probabilty distribution instead
        call BAO_DR11_init(Ini%ReadFileName('prob_dist'))
    !else
    !    allocate(this%bao_invcov(this%num_bao,this%num_bao))
    !    this%bao_invcov=0

    !    if (Ini%HasKey('bao_invcov_file')) then
    !        bao_invcov_file  = Ini%ReadFileName('bao_invcov_file')
    !        call File%ReadTextMatrix(bao_invcov_file, this%bao_invcov)
    !    else
    !        do i=1,this%num_bao
                !diagonal, or actually just 1..
    !            this%bao_invcov(i,i) = 1/this%bao_err(i)**2
    !        end do
    !    end if
    !end if

    end subroutine BAO_ReadIni

    function Acoustic(this,CMB,z)
    class(BAO_Andreu_Likelihood) :: this
    class(CMBParams) CMB
    real(mcp) Acoustic
    real(mcp), intent(IN) :: z
    real(mcp) omh2,ckm,omegam,h

    omegam = 1.d0 - CMB%omv - CMB%omk
    h = CMB%h0/100
    ckm = const_c/1e3_mcp !JD c in km/s

    omh2 = omegam*h**2.d0
    Acoustic = 100*this%Calculator%BAO_D_v(z)*sqrt(omh2)/(ckm*z)
    end function Acoustic

    function SDSS_dvtors(this, CMB,z)
    !This uses numerical value of D_v/r_s, but re-scales it to match definition of SDSS
    !paper fitting at the fiducial model. Idea being it is also valid for e.g. varying N_eff
    class(BAO_Andreu_Likelihood) :: this
    class(CMBParams) CMB
    real(mcp) SDSS_dvtors
    real(mcp), intent(IN)::z
    real(mcp) rs
    real(mcp), parameter :: rs_rescale = 153.017d0/148.92 !149.0808

    !    rs = SDSS_CMBToBAOrs(CMB)
    rs = rsdrag_theory*rs_rescale !rescaled to match fitting formula for LCDM
    SDSS_dvtors = this%Calculator%BAO_D_v(z)/rs

    end function SDSS_dvtors

   ! HS modified SDSS_dvtors to calculate D_A/rs 
    function SDSS_dAtors(this, CMB,z)
    !This uses numerical value of D_A/r_s, but re-scales it to match definition of SDSS
    !paper fitting at the fiducial model. Idea being it is also valid for e.g. varying N_eff
    class(BAO_Andreu_Likelihood) :: this
    class(CMBParams) CMB
    real(mcp) SDSS_dAtors
    real(mcp), intent(IN)::z
    real(mcp) rs
    real(mcp), parameter :: rs_rescale = 153.017d0/148.92 !149.0808

    !    rs = SDSS_CMBToBAOrs(CMB)
    rs = rsdrag_theory*rs_rescale !rescaled to match fitting formula for LCDM
    SDSS_dAtors = this%Calculator%AngularDiameterDistance(z)/rs
    end function SDSS_dAtors



    !===================================================================================

    function BAO_LnLike(this, CMB, Theory, DataParams)
    Class(BAO_Andreu_Likelihood) :: this
    Class(CMBParams) CMB
    Class(TCosmoTheoryPredictions), target :: Theory
    real(mcp) :: DataParams(:)
    integer j,k
    real(mcp) BAO_LnLike
    real(mcp), allocatable :: BAO_theory(:)

    if (BAO_fixed_rs>0) then
        !this is just for use for e.g. BAO 'only' constraints
        rsdrag_theory =  BAO_fixed_rs
    else
        rsdrag_theory =  Theory%derived_parameters( derived_rdrag )
    end if
    BAO_LnLike=0
    !if (this%name=='DR7') then
    !    BAO_LnLike = this%BAO_DR7_loglike(CMB,this%bao_z(1))
    !elseif (this%name=='DR11CMASS') then
        BAO_LnLike = this%BAO_DR11_loglike(CMB,this%bao_z(1))
    !else
    !    allocate(BAO_theory(this%num_bao))

    !    if(this%type_bao ==3)then
    !        do j=1, this%num_bao
    !            BAO_theory(j) = this%SDSS_dvtors(CMB,this%bao_z(j))
    !        end do
    !    else if(this%type_bao ==2)then
    !        do j=1, this%num_bao
    !            BAO_theory(j) = this%Acoustic(CMB,this%bao_z(j))
    !        end do
    !    else if(this%type_bao ==4)then
    !        do j=1, this%num_bao
    !            BAO_theory(j) = this%Calculator%BAO_D_v(this%bao_z(j))
    !        end do
    !    else if(this%type_bao ==5)then
    !        do j=1, this%num_bao
    !            BAO_theory(j) = this%SDSS_dAtors(CMB,this%bao_z(j))
    !        end do

    !    end if

    !    do j=1, this%num_bao
    !        do k=1, this%num_bao
    !            BAO_LnLike = BAO_LnLike +&
    !            (BAO_theory(j)-this%bao_obs(j))*this%bao_invcov(j,k)*&
    !            (BAO_theory(k)-this%bao_obs(k))
    !        end do
    !    end do
    !    BAO_LnLike = BAO_LnLike/2.d0

    !    deallocate(BAO_theory)
    !end if

    if(feedback>1) write(*,*) trim(this%name)//' BAO likelihood = ', BAO_LnLike

    end function BAO_LnLike


    subroutine BAO_DR7_init(fname)
    character(LEN=*), intent(in) :: fname
    real(mcp) :: tmp0,tmp1
    real(mcp) :: DR7_alpha =0
    integer ios,ii

    open(unit=7,file=fname,status='old')
    !Read data file
    ios = 0
    ii  = 0
    do while (ios.eq.0)
        read (7,*,iostat=ios) tmp0,tmp1
        if (ios .ne. 0) cycle
        if((ii.gt.1).and.(abs(DR7_dalpha-(tmp0-DR7_alpha)).gt.1e-6)) then
            stop 'binning should be uniform in sdss_baoDR7.txt'
        endif
        ii = ii+1
        DR7_alpha_file(ii) = tmp0
        DR7_prob_file (ii) = tmp1
        DR7_dalpha = tmp0-DR7_alpha
        DR7_alpha  = tmp0
    enddo
    DR7_alpha_npoints = ii
    if (ii.eq.0) call MpiStop('ERROR : reading file')
    close(7)
    !Normalize distribution (so that the peak value is 1.0)
    tmp0=0.0
    do ii=1,DR7_alpha_npoints
        if(DR7_prob_file(ii).gt.tmp0) then
            tmp0=DR7_prob_file(ii)
        endif
    enddo
    DR7_prob_file=DR7_prob_file/tmp0

    end subroutine BAO_DR7_init

    function BAO_DR7_loglike(this,CMB,z)
    Class(BAO_Andreu_Likelihood) :: this
    Class(CMBParams) CMB
    real (mcp) z, BAO_DR7_loglike, alpha_chain, prob
    real,parameter :: rs_wmap7=152.7934d0,dv1_wmap7=1340.177  !r_s and D_V computed for wmap7 cosmology
    integer ii
    alpha_chain = (this%SDSS_dvtors(CMB,z))/(dv1_wmap7/rs_wmap7)
    if ((alpha_chain.gt.DR7_alpha_file(DR7_alpha_npoints-1)).or.(alpha_chain.lt.DR7_alpha_file(1))) then
        BAO_DR7_loglike = logZero
    else
        ii=1+floor((alpha_chain-DR7_alpha_file(1))/DR7_dalpha)
        prob=DR7_prob_file(ii)+(DR7_prob_file(ii+1)-DR7_prob_file(ii))/ &
        (DR7_alpha_file(ii+1)-DR7_alpha_file(ii))*(alpha_chain-DR7_alpha_file(ii))
        BAO_DR7_loglike = -log( prob )
    endif

    end function BAO_DR7_loglike

    subroutine BAO_DR11_init(fname)
    character(LEN=*), intent(in) :: fname
    real(mcp) :: tmp0,tmp1,tmp2,tmp3,tmp4
    integer ios,ii,jj,nn

    open(unit=7,file=fname,status='old')
    ios = 0
    nn=0
    do while (ios.eq.0)
!JAV
        read (7,*,iostat=ios) tmp0,tmp1,tmp2
        if (ios .ne. 0) cycle
        nn = nn + 1
!JAV
!order is important
        ii = 1 +    ((nn-1)/DR11_alpha_npoints)
        jj = 1 + mod((nn-1),DR11_alpha_npoints)
        DR11_alpha_perp_file(ii)   = tmp0
        DR11_alpha_plel_file(jj)   = tmp1

!JAV
        DR11_prob_file(ii,jj)      = tmp2/2.0 !prob got from chis2
!    print *,'DR11', ii,jj,DR11_alpha_perp_file(ii),DR11_alpha_plel_file(jj)
    enddo
    close(7)



!    DR11_dalpha_perp=DR11_alpha_perp_file(2)-DR11_alpha_perp_file(1)
!    DR11_dalpha_plel=DR11_alpha_plel_file(2)-DR11_alpha_plel_file(1)
    !Normalize distribution (so that the peak value is 1.0)
!    tmp0=0.0
!    do ii=1,DR11_alpha_npoints
!        do jj=1,DR11_alpha_npoints
!            if(DR11_prob_file(ii,jj).gt.tmp0) then
!                tmp0=DR11_prob_file(ii,jj)
!            endif
!        enddo
!    enddo
!    DR11_prob_file=DR11_prob_file/tmp0

!JAV

    tmp0=1.d30

    do ii=1,DR11_alpha_npoints2
    do jj=1,DR11_alpha_npoints
       if(DR11_prob_file(ii,jj).lt.tmp0) then
          tmp0=DR11_prob_file(ii,jj)
       endif
    enddo
    enddo

!JAV
!Normalize distribution (so that the peak value is 1.0)
    do ii=1,DR11_alpha_npoints2
    do jj=1,DR11_alpha_npoints
       DR11_prob_file(ii,jj)=exp(-DR11_prob_file(ii,jj)+tmp0)
!    print *,'DR11', DR11_prob_file(ii,jj)
    enddo
     enddo


    DR11_dalpha_perp=DR11_alpha_perp_file(2)-DR11_alpha_perp_file(1)
    DR11_dalpha_plel=DR11_alpha_plel_file(2)-DR11_alpha_plel_file(1)

    end subroutine BAO_DR11_init

    function BAO_DR11_loglike(this,CMB,z)
    Class(BAO_Andreu_Likelihood) :: this
    Class(CMBParams) CMB
    real (mcp) z, BAO_DR11_loglike, alpha_perp, alpha_plel, prob
!JAV
!    real,parameter :: rd_fid=149.28,H_fid=93.558,DA_fid=1359.72 !fiducial parameters
    real,parameter ::rd_fid=149.6560,H_fid=232.184690671117,DA_fid=1731.32745289946
!    real,parameter ::rd_fid=149.5749264, H_fid=231.982225,DA_fid=1732.803860
    integer ii,jj
    alpha_perp=(this%Calculator%AngularDiameterDistance(z)/rsdrag_theory)/(DA_fid/rd_fid)
    alpha_plel=(H_fid*rd_fid)/((const_c*this%Calculator%Hofz(z)/1.d3)*rsdrag_theory)

!    print *, 'alphas', alpha_perp,alpha_plel,DR11_alpha_perp_file(1),DR11_alpha_plel_file(1)
!    print *, 'alphas2', DR11_alpha_perp_file(DR11_alpha_npoints),DR11_alpha_plel_file(DR11_alpha_npoints)

    if ((alpha_perp.lt.DR11_alpha_perp_file(1)).or.(alpha_perp.gt.DR11_alpha_perp_file(DR11_alpha_npoints2-1)).or. &
    &   (alpha_plel.lt.DR11_alpha_plel_file(1)).or.(alpha_plel.gt.DR11_alpha_plel_file(DR11_alpha_npoints-1))) then
        BAO_DR11_loglike = logZero
    else
        ii=1+floor((alpha_perp-DR11_alpha_perp_file(1))/DR11_dalpha_perp)
        jj=1+floor((alpha_plel-DR11_alpha_plel_file(1))/DR11_dalpha_plel)
        prob=(1./((DR11_alpha_perp_file(ii+1)-DR11_alpha_perp_file(ii))*(DR11_alpha_plel_file(jj+1)-DR11_alpha_plel_file(jj))))*  &
        &       (DR11_prob_file(ii,jj)*(DR11_alpha_perp_file(ii+1)-alpha_perp)*(DR11_alpha_plel_file(jj+1)-alpha_plel) &
        &       -DR11_prob_file(ii+1,jj)*(DR11_alpha_perp_file(ii)-alpha_perp)*(DR11_alpha_plel_file(jj+1)-alpha_plel) &
        &       -DR11_prob_file(ii,jj+1)*(DR11_alpha_perp_file(ii+1)-alpha_perp)*(DR11_alpha_plel_file(jj)-alpha_plel) &
        &       +DR11_prob_file(ii+1,jj+1)*(DR11_alpha_perp_file(ii)-alpha_perp)*(DR11_alpha_plel_file(jj)-alpha_plel))
        if  (prob.gt.0.) then
            BAO_DR11_loglike = -log( prob )
        else
            BAO_DR11_loglike = logZero
        endif
    endif

    end function BAO_DR11_loglike

    function SDSS_CMBToBAOrs(CMB)
    Type(CMBParams) CMB
    real(mcp) ::  rsdrag
    real(mcp) :: SDSS_CMBToBAOrs
    real(mcp) :: zeq,zdrag,omh2,obh2,b1,b2
    real(mcp) :: rd,req,wkeq

    obh2=CMB%ombh2
    omh2=CMB%ombh2+CMB%omdmh2

    b1     = 0.313*omh2**(-0.419)*(1+0.607*omh2**0.674)
    b2     = 0.238*omh2**0.223
    zdrag  = 1291.*omh2**0.251*(1.+b1*obh2**b2)/(1.+0.659*omh2**0.828)
    zeq    = 2.50e4*omh2*(2.726/2.7)**(-4.)
    wkeq   = 7.46e-2*omh2*(2.726/2.7)**(-2)
    req    = 31.5*obh2*(2.726/2.7)**(-4)*(1e3/zeq)
    rd     = 31.5*obh2*(2.726/2.7)**(-4)*(1e3/zdrag)
    rsdrag = 2./(3.*wkeq)*sqrt(6./req)*log((sqrt(1.+rd)+sqrt(rd+req))/(1.+sqrt(req)))

    SDSS_CMBToBAOrs = rsdrag

    end function SDSS_CMBToBAOrs


    end module bao_Andreu
