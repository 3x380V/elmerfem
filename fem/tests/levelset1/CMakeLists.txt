IF(HAVE_UMFPACK OR HAVE_MUMPS)
  INCLUDE(test_macros)
  INCLUDE_DIRECTORIES(${CMAKE_BINARY_DIR}/fem/src)

  CONFIGURE_FILE( round.sif round.sif COPYONLY)
  ADD_ELMERTEST_MODULE(levelset1 InitSquare InitSquare.f90)

  file(COPY square.grd ELMERSOLVER_STARTINFO InitSquare.f90  DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/")

  ADD_ELMER_TEST(levelset1 LABELS transient)
ENDIF()
