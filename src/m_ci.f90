!==================================================================
! This file is part of MOLGW.
! Author: Fabien Bruneval
!
! This module contains
! full ci calculations for a few electrons  (1, 2, 3 and 4)
! using occupation number vectors
!
!==================================================================
module m_ci
 use m_definitions
 use m_mpi
 use m_warning
 use m_tools
 use m_memory
 use m_timing
 use m_basis_set
 use m_eri_ao_mo
 use m_inputparam,only: nspin,has_auxil_basis


 real(dp),allocatable :: coeff_1e(:,:)
 real(dp),allocatable :: coeff_2e(:,:)
 real(dp),allocatable :: coeff_3e(:,:)


contains 


!==================================================================
subroutine full_ci_1electron_on(print_wfn_,nstate,spinstate,basis,h_1e,c_matrix,nuc_nuc)
 implicit none

 logical,intent(in)         :: print_wfn_
 integer,intent(in)         :: spinstate,nstate
 type(basis_set),intent(in) :: basis
 real(dp),intent(in)        :: h_1e(basis%nbf,basis%nbf),c_matrix(basis%nbf,nstate,nspin)
 real(dp),intent(in)        :: nuc_nuc
!=====
 real(dp)                   :: h_1body(nstate,nstate)
 integer                    :: isporb,jsporb,ksporb,lsporb
 integer                    :: istate,jstate,kstate,lstate
 integer                    :: ispin,jspin,kspin,lspin
 integer                    :: iisporb
 integer                    :: iistate
 integer                    :: iispin
 integer                    :: jisporb
 integer                    :: jistate
 integer                    :: jispin
 integer                    :: iconf,jconf,nconf
 real(dp),allocatable       :: h_ci(:,:),eigvec(:,:),energy(:)
 integer,allocatable        :: on_i(:),on_j(:)
 logical,allocatable        :: mask(:)
!=====

 call start_clock(timing_full_ci)

 write(stdout,'(/,1x,a,/)') 'Full CI for 1 electrons'

 select case(spinstate)
 case(-1)
   write(stdout,*) 'Any spin state'
 case(1)
   write(stdout,*) 'Spin doublet'
 case default
   call die('full_ci_2electrons: spin case not possible')
 end select

 if( .NOT. has_auxil_basis ) then
   call die('full_ci_1electrons only works with auxiliary basis')
 endif

 ! Get the 3-center integrals in the MO basis
 call calculate_eri_3center_eigen(basis%nbf,nstate,c_matrix,1,nstate,1,nstate)

 write(stdout,*) 'Obtain the one-electron Hamiltonian in the HF basis'
 h_1body(:,:) = MATMUL( TRANSPOSE(c_matrix(:,:,1)) , MATMUL( h_1e(:,:) , c_matrix(:,:,1) ) )


 !
 ! Follow the second-quantization notations from Hellgaker book Chapter 1.
 ! Use occupation number vectors on_i(:) and on_j(:) filled with 0's and three 1's.
 !

 nconf = 0
 do isporb=1,2*nstate
   ispin = 2*MODULO( isporb , 2 ) - 1
   istate = (isporb+1) / 2
   if( ispin == spinstate .OR. spinstate == -1 ) then
     nconf = nconf + 1
     write(stdout,'(1x,i6,a,3(1x,i4,1x,i2))') nconf,' :  ',istate,ispin
   endif

 enddo

 write(stdout,*) 'nconf =',nconf

 allocate(h_ci(nconf,nconf))
 allocate(on_i(2*nstate))
 allocate(on_j(2*nstate))
 allocate(mask(2*nstate))
 h_ci(:,:) = 0.0_dp

 jconf = 0
 do jisporb=1,2*nstate
   jispin = 2*MODULO( jisporb , 2 ) - 1
   jistate = (jisporb+1) / 2
   if( jispin /= spinstate .AND. spinstate /= -1) cycle
   jconf = jconf + 1

   on_j(:) = 0
   on_j(jisporb) = 1

   iconf = 0
   do iisporb=1,2*nstate
     iispin = 2*MODULO( iisporb , 2 ) - 1
     iistate = (iisporb+1) / 2

     if( iispin /= spinstate .AND. spinstate /= -1 ) cycle
     iconf = iconf + 1

     on_i(:) = 0
     on_i(iisporb) = 1


     !
     ! 1-body part
     !

     !
     ! Exact same ON-vector
     if( iconf == jconf ) then 
       do isporb=1,2*nstate
         if( on_i(isporb) == 0 ) cycle
         istate = (isporb+1) / 2
         h_ci(iconf,jconf) = h_ci(iconf,jconf) + h_1body(istate,istate)
       enddo
     endif

     !
     ! ON-vectors differ by one occupation number
     if( COUNT( on_j(:) - on_i(:) == 1 ) == 1 ) then
       jsporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 )
       isporb = MINLOC( on_j(:) - on_i(:) , DIM=1 )
       jstate = ( jsporb + 1 ) / 2
       istate = ( isporb + 1 ) / 2
       ispin = 2*MODULO( isporb , 2 ) - 1
       jspin = 2*MODULO( jsporb , 2 ) - 1

       if( ispin == jspin ) &
         h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                        + h_1body(istate,jstate) * gamma_sign(on_j,jsporb) * gamma_sign(on_i,isporb)

     endif



     !
     ! 2-body part
     !

     !
     ! Exact same ON-vector
     if( iconf == jconf ) then 
       do jsporb=1,2*nstate
         if( on_j(jsporb) == 0 ) cycle
         jstate = ( jsporb + 1 ) / 2
         jspin = 2*MODULO( jsporb , 2 ) - 1

         do isporb=1,2*nstate
           if( on_i(isporb) == 0 ) cycle
           istate = ( isporb + 1 ) / 2
           ispin = 2*MODULO( isporb , 2 ) - 1

           h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                      + 0.5_dp * eri_eigen_ri(istate,istate,1,jstate,jstate,1)

           if( ispin == jspin ) &
             h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                        - 0.5_dp * eri_eigen_ri(istate,jstate,1,jstate,istate,1)

         enddo
       enddo
     endif

     !
     ! ON-vectors differ by one occupation number
     if( COUNT( on_j(:) - on_i(:) == 1 ) == 1 ) then
       jsporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 )
       isporb = MINLOC( on_j(:) - on_i(:) , DIM=1 )
       jstate = ( jsporb + 1 ) / 2
       istate = ( isporb + 1 ) / 2
       ispin = 2*MODULO( isporb , 2 ) - 1
       jspin = 2*MODULO( jsporb , 2 ) - 1

       do ksporb=1,2*nstate
         if( on_i(ksporb) == 0 ) cycle
         if( on_j(ksporb) == 0 ) cycle
         kstate = ( ksporb + 1 ) / 2
         kspin = 2*MODULO( ksporb , 2 ) - 1

         if( ispin == jspin ) &
           h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                      + eri_eigen_ri(istate,jstate,1,kstate,kstate,1)   &
                           * gamma_sign(on_i,isporb) * gamma_sign(on_j,jsporb)

         if( ispin == kspin .AND. jspin == kspin ) &
           h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                      - eri_eigen_ri(istate,kstate,1,kstate,jstate,1)  &
                           * gamma_sign(on_i,isporb) * gamma_sign(on_j,jsporb)
       enddo

     endif

     !
     ! ON-vectors differ by one occupation number
     if( COUNT( on_j(:) - on_i(:) == 1 ) == 2 ) then
       ! Find the two indexes k < l
       ksporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 )
       mask(:)      = .TRUE.
       mask(ksporb) = .FALSE.
       lsporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 , MASK=mask)

       ! Find the two indexes i < j
       isporb = MINLOC( on_j(:) - on_i(:) , DIM=1 )
       mask(:)      = .TRUE.
       mask(isporb) = .FALSE.
       jsporb = MINLOC( on_j(:) - on_i(:) , DIM=1 , MASK=mask)

       istate = ( isporb + 1 ) / 2
       jstate = ( jsporb + 1 ) / 2
       kstate = ( ksporb + 1 ) / 2
       lstate = ( lsporb + 1 ) / 2
       ispin = 2*MODULO( isporb , 2 ) - 1
       jspin = 2*MODULO( jsporb , 2 ) - 1
       kspin = 2*MODULO( ksporb , 2 ) - 1
       lspin = 2*MODULO( lsporb , 2 ) - 1

       if( ispin == kspin .AND. jspin == lspin ) &
         h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                    + eri_eigen_ri(istate,kstate,1,jstate,lstate,1)           &
                         * gamma_sign(on_i,isporb) * gamma_sign(on_i,jsporb)  &
                         * gamma_sign(on_j,ksporb) * gamma_sign(on_j,lsporb)

       if( ispin == lspin .AND. jspin == kspin ) &
         h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                    - eri_eigen_ri(istate,lstate,1,jstate,kstate,1)           &
                         * gamma_sign(on_i,isporb) * gamma_sign(on_i,jsporb)  &
                         * gamma_sign(on_j,ksporb) * gamma_sign(on_j,lsporb)

     endif


   enddo

 enddo

 deallocate(mask,on_i,on_j)

 allocate(energy(nconf))
 allocate(eigvec(nconf,nconf))

 call diagonalize(nconf,h_ci,energy,eigvec)

 write(stdout,'(/,1x,a,f19.10,/)') '      Correlation energy (Ha): ',energy(1) - h_ci(1,1)
 write(stdout,'(1x,a,f19.10)')     '     Ground-state energy (Ha): ',energy(1) + nuc_nuc
 write(stdout,'(1x,a,f19.10)')     '1st excited-state energy (Ha): ',energy(2) + nuc_nuc
 write(stdout,'(1x,a,f19.10)')     '2nd excited-state energy (Ha): ',energy(3) + nuc_nuc
 write(stdout,'(1x,a,f19.10)')     '3rd excited-state energy (Ha): ',energy(4) + nuc_nuc
 write(stdout,'(1x,a,f19.10)')     '4th excited-state energy (Ha): ',energy(5) + nuc_nuc


 deallocate(h_ci,eigvec,energy)

 call destroy_eri_3center_eigen()

 call stop_clock(timing_full_ci)


end subroutine full_ci_1electron_on


!==================================================================
subroutine full_ci_2electrons_on(print_wfn_,nstate,spinstate,basis,h_1e,c_matrix,nuc_nuc)
 implicit none

 logical,intent(in)         :: print_wfn_
 integer,intent(in)         :: spinstate,nstate
 type(basis_set),intent(in) :: basis
 real(dp),intent(in)        :: h_1e(basis%nbf,basis%nbf),c_matrix(basis%nbf,nstate,nspin)
 real(dp),intent(in)        :: nuc_nuc
!=====
 real(dp)                   :: h_1body(nstate,nstate)
 integer                    :: isporb,jsporb,ksporb,lsporb
 integer                    :: istate,jstate,kstate,lstate
 integer                    :: ispin,jspin,kspin,lspin
 integer                    :: iisporb,ijsporb
 integer                    :: iistate,ijstate
 integer                    :: iispin,ijspin
 integer                    :: jisporb,jjsporb
 integer                    :: jistate,jjstate
 integer                    :: jispin,jjspin
 integer                    :: iconf,jconf,nconf
 real(dp),allocatable       :: h_ci(:,:),eigvec(:,:),energy(:)
 integer,allocatable        :: on_i(:),on_j(:)
 logical,allocatable        :: mask(:)
!=====

 call start_clock(timing_full_ci)

 write(stdout,'(/,1x,a,/)') 'Full CI for 2 electrons'

 select case(spinstate)
 case(-1)
   write(stdout,*) 'Any spin state'
 case(0)
   write(stdout,*) 'Spin singlet'
 case(2)
   write(stdout,*) 'Spin triplet'
 case default
   call die('full_ci_2electrons: spin case not possible')
 end select

 if( .NOT. has_auxil_basis ) then
   call die('full_ci_2electrons only works with auxiliary basis')
 endif

 ! Get the 3-center integrals in the MO basis
 call calculate_eri_3center_eigen(basis%nbf,nstate,c_matrix,1,nstate,1,nstate)

 write(stdout,*) 'Obtain the one-electron Hamiltonian in the HF basis'
 h_1body(:,:) = MATMUL( TRANSPOSE(c_matrix(:,:,1)) , MATMUL( h_1e(:,:) , c_matrix(:,:,1) ) )


 !
 ! Follow the second-quantization notations from Hellgaker book Chapter 1.
 ! Use occupation number vectors on_i(:) and on_j(:) filled with 0's and three 1's.
 !

 nconf = 0
 do jsporb=1,2*nstate
   do isporb=jsporb+1,2*nstate
     ispin = 2*MODULO( isporb , 2 ) - 1
     jspin = 2*MODULO( jsporb , 2 ) - 1
     istate = (isporb+1) / 2
     jstate = (jsporb+1) / 2
     if( ispin + jspin == spinstate .OR. spinstate == -1 ) then
       nconf = nconf + 1
       write(stdout,'(1x,i6,a,3(1x,i4,1x,i2))') nconf,' :  ',istate,ispin,jstate,jspin
     endif

   enddo
 enddo

 write(stdout,*) 'nconf =',nconf

 allocate(h_ci(nconf,nconf))
 allocate(on_i(2*nstate))
 allocate(on_j(2*nstate))
 allocate(mask(2*nstate))
 h_ci(:,:) = 0.0_dp

 jconf = 0
 do jjsporb=1,2*nstate
   do jisporb=jjsporb+1,2*nstate
     jispin = 2*MODULO( jisporb , 2 ) - 1
     jjspin = 2*MODULO( jjsporb , 2 ) - 1
     jistate = (jisporb+1) / 2
     jjstate = (jjsporb+1) / 2
     if( jispin + jjspin /= spinstate .AND. spinstate /= -1) cycle
     jconf = jconf + 1

     on_j(:) = 0
     on_j(jisporb) = 1
     on_j(jjsporb) = 1

     iconf = 0
     do ijsporb=1,2*nstate
       do iisporb=ijsporb+1,2*nstate
         iispin = 2*MODULO( iisporb , 2 ) - 1
         ijspin = 2*MODULO( ijsporb , 2 ) - 1
         iistate = (iisporb+1) / 2
         ijstate = (ijsporb+1) / 2

         if( iispin + ijspin /= spinstate .AND. spinstate /= -1 ) cycle
         iconf = iconf + 1

         on_i(:) = 0
         on_i(iisporb) = 1
         on_i(ijsporb) = 1


         !
         ! 1-body part
         !

         !
         ! Exact same ON-vector
         if( iconf == jconf ) then 
           do isporb=1,2*nstate
             if( on_i(isporb) == 0 ) cycle
             istate = (isporb+1) / 2
             h_ci(iconf,jconf) = h_ci(iconf,jconf) + h_1body(istate,istate)
           enddo
         endif

         !
         ! ON-vectors differ by one occupation number
         if( COUNT( on_j(:) - on_i(:) == 1 ) == 1 ) then
           jsporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 )
           isporb = MINLOC( on_j(:) - on_i(:) , DIM=1 )
           jstate = ( jsporb + 1 ) / 2
           istate = ( isporb + 1 ) / 2
           ispin = 2*MODULO( isporb , 2 ) - 1
           jspin = 2*MODULO( jsporb , 2 ) - 1

           if( ispin == jspin ) &
             h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                            + h_1body(istate,jstate) * gamma_sign(on_j,jsporb) * gamma_sign(on_i,isporb)

         endif



         !
         ! 2-body part
         !

         !
         ! Exact same ON-vector
         if( iconf == jconf ) then 
           do jsporb=1,2*nstate
             if( on_j(jsporb) == 0 ) cycle
             jstate = ( jsporb + 1 ) / 2
             jspin = 2*MODULO( jsporb , 2 ) - 1

             do isporb=1,2*nstate
               if( on_i(isporb) == 0 ) cycle
               istate = ( isporb + 1 ) / 2
               ispin = 2*MODULO( isporb , 2 ) - 1

               h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                          + 0.5_dp * eri_eigen_ri(istate,istate,1,jstate,jstate,1)

               if( ispin == jspin ) &
                 h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                            - 0.5_dp * eri_eigen_ri(istate,jstate,1,jstate,istate,1)

             enddo
           enddo
         endif

         !
         ! ON-vectors differ by one occupation number
         if( COUNT( on_j(:) - on_i(:) == 1 ) == 1 ) then
           jsporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 )
           isporb = MINLOC( on_j(:) - on_i(:) , DIM=1 )
           jstate = ( jsporb + 1 ) / 2
           istate = ( isporb + 1 ) / 2
           ispin = 2*MODULO( isporb , 2 ) - 1
           jspin = 2*MODULO( jsporb , 2 ) - 1

           do ksporb=1,2*nstate
             if( on_i(ksporb) == 0 ) cycle
             if( on_j(ksporb) == 0 ) cycle
             kstate = ( ksporb + 1 ) / 2
             kspin = 2*MODULO( ksporb , 2 ) - 1

             if( ispin == jspin ) &
               h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                          + eri_eigen_ri(istate,jstate,1,kstate,kstate,1)   &
                               * gamma_sign(on_i,isporb) * gamma_sign(on_j,jsporb)

             if( ispin == kspin .AND. jspin == kspin ) &
               h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                          - eri_eigen_ri(istate,kstate,1,kstate,jstate,1)  &
                               * gamma_sign(on_i,isporb) * gamma_sign(on_j,jsporb)
           enddo

         endif

         !
         ! ON-vectors differ by one occupation number
         if( COUNT( on_j(:) - on_i(:) == 1 ) == 2 ) then
           ! Find the two indexes k < l
           ksporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 )
           mask(:)      = .TRUE.
           mask(ksporb) = .FALSE.
           lsporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 , MASK=mask)

           ! Find the two indexes i < j
           isporb = MINLOC( on_j(:) - on_i(:) , DIM=1 )
           mask(:)      = .TRUE.
           mask(isporb) = .FALSE.
           jsporb = MINLOC( on_j(:) - on_i(:) , DIM=1 , MASK=mask)

           istate = ( isporb + 1 ) / 2
           jstate = ( jsporb + 1 ) / 2
           kstate = ( ksporb + 1 ) / 2
           lstate = ( lsporb + 1 ) / 2
           ispin = 2*MODULO( isporb , 2 ) - 1
           jspin = 2*MODULO( jsporb , 2 ) - 1
           kspin = 2*MODULO( ksporb , 2 ) - 1
           lspin = 2*MODULO( lsporb , 2 ) - 1

           if( ispin == kspin .AND. jspin == lspin ) &
             h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                        + eri_eigen_ri(istate,kstate,1,jstate,lstate,1)           &
                             * gamma_sign(on_i,isporb) * gamma_sign(on_i,jsporb)  &
                             * gamma_sign(on_j,ksporb) * gamma_sign(on_j,lsporb)

           if( ispin == lspin .AND. jspin == kspin ) &
             h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                        - eri_eigen_ri(istate,lstate,1,jstate,kstate,1)           &
                             * gamma_sign(on_i,isporb) * gamma_sign(on_i,jsporb)  &
                             * gamma_sign(on_j,ksporb) * gamma_sign(on_j,lsporb)

         endif


       enddo
     enddo

   enddo
 enddo

 deallocate(mask,on_i,on_j)

 allocate(energy(nconf))
 allocate(eigvec(nconf,nconf))

 call diagonalize(nconf,h_ci,energy,eigvec)

 write(stdout,'(/,1x,a,f19.10,/)') '      Correlation energy (Ha): ',energy(1) - h_ci(1,1)
 write(stdout,'(1x,a,f19.10)')     '     Ground-state energy (Ha): ',energy(1) + nuc_nuc
 write(stdout,'(1x,a,f19.10)')     '1st excited-state energy (Ha): ',energy(2) + nuc_nuc
 write(stdout,'(1x,a,f19.10)')     '2nd excited-state energy (Ha): ',energy(3) + nuc_nuc
 write(stdout,'(1x,a,f19.10)')     '3rd excited-state energy (Ha): ',energy(4) + nuc_nuc
 write(stdout,'(1x,a,f19.10)')     '4th excited-state energy (Ha): ',energy(5) + nuc_nuc


 deallocate(h_ci,eigvec,energy)

 call destroy_eri_3center_eigen()

 call stop_clock(timing_full_ci)


end subroutine full_ci_2electrons_on


!==================================================================
subroutine full_ci_3electrons_on(print_wfn_,nstate,spinstate,basis,h_1e,c_matrix,nuc_nuc)
 implicit none

 logical,intent(in)         :: print_wfn_
 integer,intent(in)         :: spinstate,nstate
 type(basis_set),intent(in) :: basis
 real(dp),intent(in)        :: h_1e(basis%nbf,basis%nbf),c_matrix(basis%nbf,nstate,nspin)
 real(dp),intent(in)        :: nuc_nuc
!=====
 real(dp)                   :: h_1body(nstate,nstate)
 integer                    :: isporb,jsporb,ksporb,lsporb
 integer                    :: istate,jstate,kstate,lstate
 integer                    :: ispin,jspin,kspin,lspin
 integer                    :: iisporb,ijsporb,iksporb
 integer                    :: iistate,ijstate,ikstate
 integer                    :: iispin,ijspin,ikspin
 integer                    :: jisporb,jjsporb,jksporb
 integer                    :: jistate,jjstate,jkstate
 integer                    :: jispin,jjspin,jkspin
 integer                    :: iconf,jconf,nconf
 real(dp),allocatable       :: h_ci(:,:),eigvec(:,:),energy(:)
 integer,allocatable        :: on_i(:),on_j(:)
 logical,allocatable        :: mask(:)
!=====

 call start_clock(timing_full_ci)

 write(stdout,'(/,1x,a,/)') 'Full CI for 3 electrons'

 select case(spinstate)
 case(1)
   write(stdout,*) 'Spin doublet'
 case(3)
   write(stdout,*) 'Spin quadruplet'
 case default
   call die('full_ci_3electrons: spin case not possible')
 end select

 if( .NOT. has_auxil_basis ) then
   call die('full_ci_3electrons only works with auxiliary basis')
 endif

 ! Get the 3-center integrals in the MO basis
 call calculate_eri_3center_eigen(basis%nbf,nstate,c_matrix,1,nstate,1,nstate)

 write(stdout,*) 'Obtain the one-electron Hamiltonian in the HF basis'
 h_1body(:,:) = MATMUL( TRANSPOSE(c_matrix(:,:,1)) , MATMUL( h_1e(:,:) , c_matrix(:,:,1) ) )


 !
 ! Follow the second-quantization notations from Hellgaker book Chapter 1.
 ! Use occupation number vectors on_i(:) and on_j(:) filled with 0's and three 1's.
 !

 nconf = 0
 do ksporb=1,2*nstate
   do jsporb=ksporb+1,2*nstate
     do isporb=jsporb+1,2*nstate
       ispin = 2*MODULO( isporb , 2 ) - 1
       jspin = 2*MODULO( jsporb , 2 ) - 1
       kspin = 2*MODULO( ksporb , 2 ) - 1
       istate = (isporb+1) / 2
       jstate = (jsporb+1) / 2
       kstate = (ksporb+1) / 2
       if( ispin + jspin + kspin == spinstate ) then
         nconf = nconf + 1
         write(stdout,'(1x,i6,a,3(1x,i4,1x,i2))') nconf,' :  ',istate,ispin,jstate,jspin,kstate,kspin
       endif

     enddo
   enddo
 enddo

 write(stdout,*) 'nconf =',nconf

 allocate(h_ci(nconf,nconf))
 allocate(on_i(2*nstate))
 allocate(on_j(2*nstate))
 allocate(mask(2*nstate))
 h_ci(:,:) = 0.0_dp

 jconf = 0
 do jksporb=1,2*nstate
   do jjsporb=jksporb+1,2*nstate
     do jisporb=jjsporb+1,2*nstate
       jispin = 2*MODULO( jisporb , 2 ) - 1
       jjspin = 2*MODULO( jjsporb , 2 ) - 1
       jkspin = 2*MODULO( jksporb , 2 ) - 1
       jistate = (jisporb+1) / 2
       jjstate = (jjsporb+1) / 2
       jkstate = (jksporb+1) / 2
       if( jispin + jjspin + jkspin /= spinstate ) cycle
       jconf = jconf + 1

       on_j(:) = 0
       on_j(jisporb) = 1
       on_j(jjsporb) = 1
       on_j(jksporb) = 1

       iconf = 0
       do iksporb=1,2*nstate
         do ijsporb=iksporb+1,2*nstate
           do iisporb=ijsporb+1,2*nstate
             iispin = 2*MODULO( iisporb , 2 ) - 1
             ijspin = 2*MODULO( ijsporb , 2 ) - 1
             ikspin = 2*MODULO( iksporb , 2 ) - 1
             iistate = (iisporb+1) / 2
             ijstate = (ijsporb+1) / 2
             ikstate = (iksporb+1) / 2

             if( iispin + ijspin + ikspin /= spinstate ) cycle
             iconf = iconf + 1

             on_i(:) = 0
             on_i(iisporb) = 1
             on_i(ijsporb) = 1
             on_i(iksporb) = 1

!             write(*,*) 'I=',iconf,on_i(:)
!             write(*,*) 'J=',jconf,on_j(:)
!             write(*,*) COUNT( on_j(:) - on_i(:) == 1 )
!             write(*,*)

             !
             ! 1-body part
             !

             !
             ! Exact same ON-vector
             if( iconf == jconf ) then 
               do isporb=1,2*nstate
                 if( on_i(isporb) == 0 ) cycle
                 istate = (isporb+1) / 2
                 h_ci(iconf,jconf) = h_ci(iconf,jconf) + h_1body(istate,istate)
               enddo
             endif

             !
             ! ON-vectors differ by one occupation number
             if( COUNT( on_j(:) - on_i(:) == 1 ) == 1 ) then
               jsporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 )
               isporb = MINLOC( on_j(:) - on_i(:) , DIM=1 )
               jstate = ( jsporb + 1 ) / 2
               istate = ( isporb + 1 ) / 2
               ispin = 2*MODULO( isporb , 2 ) - 1
               jspin = 2*MODULO( jsporb , 2 ) - 1

               if( ispin == jspin ) &
                 h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                                + h_1body(istate,jstate) * gamma_sign(on_j,jsporb) * gamma_sign(on_i,isporb)

             endif



             !
             ! 2-body part
             !

             !
             ! Exact same ON-vector
             if( iconf == jconf ) then 
               do jsporb=1,2*nstate
                 if( on_j(jsporb) == 0 ) cycle
                 jstate = ( jsporb + 1 ) / 2
                 jspin = 2*MODULO( jsporb , 2 ) - 1

                 do isporb=1,2*nstate
                   if( on_i(isporb) == 0 ) cycle
                   istate = ( isporb + 1 ) / 2
                   ispin = 2*MODULO( isporb , 2 ) - 1

                   h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                              + 0.5_dp * eri_eigen_ri(istate,istate,1,jstate,jstate,1)

                   if( ispin == jspin ) &
                     h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                                - 0.5_dp * eri_eigen_ri(istate,jstate,1,jstate,istate,1)

                 enddo
               enddo
             endif

             !
             ! ON-vectors differ by one occupation number
             if( COUNT( on_j(:) - on_i(:) == 1 ) == 1 ) then
               jsporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 )
               isporb = MINLOC( on_j(:) - on_i(:) , DIM=1 )
               jstate = ( jsporb + 1 ) / 2
               istate = ( isporb + 1 ) / 2
               ispin = 2*MODULO( isporb , 2 ) - 1
               jspin = 2*MODULO( jsporb , 2 ) - 1

               do ksporb=1,2*nstate
                 if( on_i(ksporb) == 0 ) cycle
                 if( on_j(ksporb) == 0 ) cycle
                 kstate = ( ksporb + 1 ) / 2
                 kspin = 2*MODULO( ksporb , 2 ) - 1

                 if( ispin == jspin ) &
                   h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                              + eri_eigen_ri(istate,jstate,1,kstate,kstate,1)   &
                                   * gamma_sign(on_i,isporb) * gamma_sign(on_j,jsporb)

                 if( ispin == kspin .AND. jspin == kspin ) &
                   h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                              - eri_eigen_ri(istate,kstate,1,kstate,jstate,1)  &
                                   * gamma_sign(on_i,isporb) * gamma_sign(on_j,jsporb)
               enddo

             endif

             !
             ! ON-vectors differ by one occupation number
             if( COUNT( on_j(:) - on_i(:) == 1 ) == 2 ) then
               ! Find the two indexes k < l
               ksporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 )
               mask(:)      = .TRUE.
               mask(ksporb) = .FALSE.
               lsporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 , MASK=mask)

               ! Find the two indexes i < j
               isporb = MINLOC( on_j(:) - on_i(:) , DIM=1 )
               mask(:)      = .TRUE.
               mask(isporb) = .FALSE.
               jsporb = MINLOC( on_j(:) - on_i(:) , DIM=1 , MASK=mask)

               istate = ( isporb + 1 ) / 2
               jstate = ( jsporb + 1 ) / 2
               kstate = ( ksporb + 1 ) / 2
               lstate = ( lsporb + 1 ) / 2
               ispin = 2*MODULO( isporb , 2 ) - 1
               jspin = 2*MODULO( jsporb , 2 ) - 1
               kspin = 2*MODULO( ksporb , 2 ) - 1
               lspin = 2*MODULO( lsporb , 2 ) - 1

               if( ispin == kspin .AND. jspin == lspin ) &
                 h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                            + eri_eigen_ri(istate,kstate,1,jstate,lstate,1)           &
                                 * gamma_sign(on_i,isporb) * gamma_sign(on_i,jsporb)  &
                                 * gamma_sign(on_j,ksporb) * gamma_sign(on_j,lsporb)

               if( ispin == lspin .AND. jspin == kspin ) &
                 h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                            - eri_eigen_ri(istate,lstate,1,jstate,kstate,1)           &
                                 * gamma_sign(on_i,isporb) * gamma_sign(on_i,jsporb)  &
                                 * gamma_sign(on_j,ksporb) * gamma_sign(on_j,lsporb)

             endif


           enddo
         enddo
       enddo

     enddo
   enddo
 enddo

 deallocate(mask,on_i,on_j)

 allocate(energy(nconf))
 allocate(eigvec(nconf,nconf))

 call diagonalize(nconf,h_ci,energy,eigvec)

 write(stdout,'(/,1x,a,f19.10,/)') '      Correlation energy (Ha): ',energy(1) - h_ci(1,1)
 write(stdout,'(1x,a,f19.10)')     '     Ground-state energy (Ha): ',energy(1) + nuc_nuc
 write(stdout,'(1x,a,f19.10)')     '1st excited-state energy (Ha): ',energy(2) + nuc_nuc
 write(stdout,'(1x,a,f19.10)')     '2nd excited-state energy (Ha): ',energy(3) + nuc_nuc


 deallocate(h_ci,eigvec,energy)

 call destroy_eri_3center_eigen()

 call stop_clock(timing_full_ci)


end subroutine full_ci_3electrons_on


!==================================================================
subroutine full_ci_4electrons_on(print_wfn_,nstate,spinstate,basis,h_1e,c_matrix,nuc_nuc)
 implicit none

 logical,intent(in)         :: print_wfn_
 integer,intent(in)         :: spinstate,nstate
 type(basis_set),intent(in) :: basis
 real(dp),intent(in)        :: h_1e(basis%nbf,basis%nbf),c_matrix(basis%nbf,nstate,nspin)
 real(dp),intent(in)        :: nuc_nuc
!=====
 real(dp)                   :: h_1body(nstate,nstate)
 integer                    :: isporb,jsporb,ksporb,lsporb
 integer                    :: istate,jstate,kstate,lstate
 integer                    :: ispin,jspin,kspin,lspin
 integer                    :: iisporb,ijsporb,iksporb,ilsporb
 integer                    :: iistate,ijstate,ikstate,ilstate
 integer                    :: iispin,ijspin,ikspin,ilspin
 integer                    :: jisporb,jjsporb,jksporb,jlsporb
 integer                    :: jistate,jjstate,jkstate,jlstate
 integer                    :: jispin,jjspin,jkspin,jlspin
 integer                    :: iconf,jconf,nconf
 real(dp),allocatable       :: h_ci(:,:),eigvec(:,:),energy(:)
 integer,allocatable        :: on_i(:),on_j(:)
 logical,allocatable        :: mask(:)
!=====

 call start_clock(timing_full_ci)

 write(stdout,'(/,1x,a,/)') 'Full CI for 4 electrons'

 select case(spinstate)
 case(0)
   write(stdout,*) 'Spin singlet'
 case(2)
   write(stdout,*) 'Spin triplet'
 case(4)
   write(stdout,*) 'Spin quadruplet'
 case default
   call die('full_ci_4electrons: spin case not possible')
 end select

 if( .NOT. has_auxil_basis ) then
   call die('full_ci_3electrons only works with auxiliary basis')
 endif

 ! Get the 3-center integrals in the MO basis
 call calculate_eri_3center_eigen(basis%nbf,nstate,c_matrix,1,nstate,1,nstate)

 write(stdout,*) 'Obtain the one-electron Hamiltonian in the HF basis'
 h_1body(:,:) = MATMUL( TRANSPOSE(c_matrix(:,:,1)) , MATMUL( h_1e(:,:) , c_matrix(:,:,1) ) )


 !
 ! Follow the second-quantization notations from Hellgaker book Chapter 1.
 ! Use occupation number vectors on_i(:) and on_j(:) filled with 0's and four 1's.
 !

 nconf = 0
 do lsporb=1,2*nstate
   do ksporb=lsporb+1,2*nstate
     do jsporb=ksporb+1,2*nstate
       do isporb=jsporb+1,2*nstate
         ispin = 2*MODULO( isporb , 2 ) - 1
         jspin = 2*MODULO( jsporb , 2 ) - 1
         kspin = 2*MODULO( ksporb , 2 ) - 1
         lspin = 2*MODULO( lsporb , 2 ) - 1
         istate = (isporb+1) / 2
         jstate = (jsporb+1) / 2
         kstate = (ksporb+1) / 2
         lstate = (lsporb+1) / 2
         if( ispin + jspin + kspin + lspin == spinstate ) then
           nconf = nconf + 1
           write(stdout,'(1x,i6,a,4(1x,i4,1x,i2))') nconf,' :  ',istate,ispin,jstate,jspin,kstate,kspin,lstate,lspin
         endif

       enddo
     enddo
   enddo
 enddo

 write(stdout,*) 'nconf =',nconf

 allocate(h_ci(nconf,nconf))
 allocate(on_i(2*nstate))
 allocate(on_j(2*nstate))
 allocate(mask(2*nstate))
 h_ci(:,:) = 0.0_dp

 jconf = 0
 do jlsporb=1,2*nstate
   do jksporb=jlsporb+1,2*nstate
     do jjsporb=jksporb+1,2*nstate
       do jisporb=jjsporb+1,2*nstate
         jispin = 2*MODULO( jisporb , 2 ) - 1
         jjspin = 2*MODULO( jjsporb , 2 ) - 1
         jkspin = 2*MODULO( jksporb , 2 ) - 1
         jlspin = 2*MODULO( jlsporb , 2 ) - 1
         jistate = (jisporb+1) / 2
         jjstate = (jjsporb+1) / 2
         jkstate = (jksporb+1) / 2
         jlstate = (jksporb+1) / 2

         if( jispin + jjspin + jkspin + jlspin /= spinstate ) cycle
         jconf = jconf + 1

         on_j(:) = 0
         on_j(jisporb) = 1
         on_j(jjsporb) = 1
         on_j(jksporb) = 1
         on_j(jlsporb) = 1

         iconf = 0
         do ilsporb=1,2*nstate
           do iksporb=ilsporb+1,2*nstate
             do ijsporb=iksporb+1,2*nstate
               do iisporb=ijsporb+1,2*nstate
                 iispin = 2*MODULO( iisporb , 2 ) - 1
                 ijspin = 2*MODULO( ijsporb , 2 ) - 1
                 ikspin = 2*MODULO( iksporb , 2 ) - 1
                 ilspin = 2*MODULO( ilsporb , 2 ) - 1
                 iistate = (iisporb+1) / 2
                 ijstate = (ijsporb+1) / 2
                 ikstate = (iksporb+1) / 2
                 ilstate = (ilsporb+1) / 2

                 if( iispin + ijspin + ikspin + ilspin /= spinstate ) cycle
                 iconf = iconf + 1

                 on_i(:) = 0
                 on_i(iisporb) = 1
                 on_i(ijsporb) = 1
                 on_i(iksporb) = 1
                 on_i(ilsporb) = 1


                 !
                 ! 1-body part
                 !

                 !
                 ! Exact same ON-vector
                 if( iconf == jconf ) then 
                   do isporb=1,2*nstate
                     if( on_i(isporb) == 0 ) cycle
                     istate = (isporb+1) / 2
                     h_ci(iconf,jconf) = h_ci(iconf,jconf) + h_1body(istate,istate)
                   enddo
                 endif

                 !
                 ! ON-vectors differ by one occupation number
                 if( COUNT( on_j(:) - on_i(:) == 1 ) == 1 ) then
                   jsporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 )
                   isporb = MINLOC( on_j(:) - on_i(:) , DIM=1 )
                   jstate = ( jsporb + 1 ) / 2
                   istate = ( isporb + 1 ) / 2
                   ispin = 2*MODULO( isporb , 2 ) - 1
                   jspin = 2*MODULO( jsporb , 2 ) - 1

                   if( ispin == jspin ) &
                     h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                                    + h_1body(istate,jstate) * gamma_sign(on_j,jsporb) * gamma_sign(on_i,isporb)

                 endif



                 !
                 ! 2-body part
                 !

                 !
                 ! Exact same ON-vector
                 if( iconf == jconf ) then 
                   do jsporb=1,2*nstate
                     if( on_j(jsporb) == 0 ) cycle
                     jstate = ( jsporb + 1 ) / 2
                     jspin = 2*MODULO( jsporb , 2 ) - 1

                     do isporb=1,2*nstate
                       if( on_i(isporb) == 0 ) cycle
                       istate = ( isporb + 1 ) / 2
                       ispin = 2*MODULO( isporb , 2 ) - 1

                       h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                                  + 0.5_dp * eri_eigen_ri(istate,istate,1,jstate,jstate,1)

                       if( ispin == jspin ) &
                         h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                                    - 0.5_dp * eri_eigen_ri(istate,jstate,1,jstate,istate,1)

                     enddo
                   enddo
                 endif

                 !
                 ! ON-vectors differ by one occupation number
                 if( COUNT( on_j(:) - on_i(:) == 1 ) == 1 ) then
                   jsporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 )
                   isporb = MINLOC( on_j(:) - on_i(:) , DIM=1 )
                   jstate = ( jsporb + 1 ) / 2
                   istate = ( isporb + 1 ) / 2
                   ispin = 2*MODULO( isporb , 2 ) - 1
                   jspin = 2*MODULO( jsporb , 2 ) - 1

                   do ksporb=1,2*nstate
                     if( on_i(ksporb) == 0 ) cycle
                     if( on_j(ksporb) == 0 ) cycle
                     kstate = ( ksporb + 1 ) / 2
                     kspin = 2*MODULO( ksporb , 2 ) - 1

                     if( ispin == jspin ) &
                       h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                                  + eri_eigen_ri(istate,jstate,1,kstate,kstate,1)   &
                                       * gamma_sign(on_i,isporb) * gamma_sign(on_j,jsporb)

                     if( ispin == kspin .AND. jspin == kspin ) &
                       h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                                  - eri_eigen_ri(istate,kstate,1,kstate,jstate,1)  &
                                       * gamma_sign(on_i,isporb) * gamma_sign(on_j,jsporb)
                   enddo

                 endif

                 !
                 ! ON-vectors differ by one occupation number
                 if( COUNT( on_j(:) - on_i(:) == 1 ) == 2 ) then
                   ! Find the two indexes k < l
                   ksporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 )
                   mask(:)      = .TRUE.
                   mask(ksporb) = .FALSE.
                   lsporb = MAXLOC( on_j(:) - on_i(:) , DIM=1 , MASK=mask)

                   ! Find the two indexes i < j
                   isporb = MINLOC( on_j(:) - on_i(:) , DIM=1 )
                   mask(:)      = .TRUE.
                   mask(isporb) = .FALSE.
                   jsporb = MINLOC( on_j(:) - on_i(:) , DIM=1 , MASK=mask)

                   istate = ( isporb + 1 ) / 2
                   jstate = ( jsporb + 1 ) / 2
                   kstate = ( ksporb + 1 ) / 2
                   lstate = ( lsporb + 1 ) / 2
                   ispin = 2*MODULO( isporb , 2 ) - 1
                   jspin = 2*MODULO( jsporb , 2 ) - 1
                   kspin = 2*MODULO( ksporb , 2 ) - 1
                   lspin = 2*MODULO( lsporb , 2 ) - 1

                   if( ispin == kspin .AND. jspin == lspin ) &
                     h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                                + eri_eigen_ri(istate,kstate,1,jstate,lstate,1)           &
                                     * gamma_sign(on_i,isporb) * gamma_sign(on_i,jsporb)  &
                                     * gamma_sign(on_j,ksporb) * gamma_sign(on_j,lsporb)

                   if( ispin == lspin .AND. jspin == kspin ) &
                     h_ci(iconf,jconf) = h_ci(iconf,jconf)  &
                                - eri_eigen_ri(istate,lstate,1,jstate,kstate,1)           &
                                     * gamma_sign(on_i,isporb) * gamma_sign(on_i,jsporb)  &
                                     * gamma_sign(on_j,ksporb) * gamma_sign(on_j,lsporb)

                 endif


               enddo
             enddo
           enddo
         enddo

       enddo
     enddo
   enddo
 enddo

 deallocate(mask,on_i,on_j)

 allocate(energy(nconf))
 allocate(eigvec(nconf,nconf))

 call diagonalize(nconf,h_ci,energy,eigvec)

 write(stdout,'(/,1x,a,f19.10,/)') '      Correlation energy (Ha): ',energy(1) - h_ci(1,1)
 write(stdout,'(1x,a,f19.10)')     '     Ground-state energy (Ha): ',energy(1) + nuc_nuc
 write(stdout,'(1x,a,f19.10)')     '1st excited-state energy (Ha): ',energy(2) + nuc_nuc
 write(stdout,'(1x,a,f19.10)')     '2nd excited-state energy (Ha): ',energy(3) + nuc_nuc


 deallocate(h_ci,eigvec,energy)

 call destroy_eri_3center_eigen()

 call stop_clock(timing_full_ci)


end subroutine full_ci_4electrons_on


!==================================================================
pure function gamma_sign(conf,isporb)
 implicit none

 integer,intent(in) :: conf(:)
 integer,intent(in) :: isporb
 integer            :: gamma_sign
!=====
!=====

 gamma_sign = 1 - 2 * MODULO( COUNT( conf(1:isporb-1) == 1 ) , 2 ) 

end function gamma_sign


end module m_ci
!==================================================================
