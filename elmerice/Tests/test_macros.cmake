MACRO(ADD_ELMERICE_LABEL test_name label_string)
  SET_PROPERTY(TEST ${test_name} APPEND PROPERTY LABELS ${label_string})
ENDMACRO()

MACRO(ADD_ELMERICE_TEST test_name)
  ADD_TEST(NAME ${test_name}
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    COMMAND ${CMAKE_COMMAND}
      -DELMERGRID_BIN=${ELMERGRID_BIN}
      -DELMERSOLVER_BIN=${ELMERSOLVER_BIN}
      -DTEST_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}
      -DPROJECT_SOURCE_DIR=${PROJECT_SOURCE_DIR}
      -DBINARY_DIR=${CMAKE_BINARY_DIR}
      -DELMERSOLVER_HOME=${ELMER_SOLVER_HOME}
      -DSHLEXT=${SHL_EXTENSION}
      -DCMAKE_Fortran_COMPILER=${CMAKE_Fortran_COMPILER}
      -DMPIEXEC=${MPIEXEC}
      -DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}
      -DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}
      -DMPIEXEC_POSTFLAGS=${MPIEXEC_POSTFLAGS}
      -DWITH_MPI=${WITH_MPI}
      -P ${CMAKE_CURRENT_SOURCE_DIR}/runTest.cmake)
  SET_TESTS_PROPERTIES(${test_name} PROPERTIES LABELS "elmerice")
ENDMACRO()

MACRO(ADD_ELMERICETEST_MODULE test_name module_name file_name)
  IF(APPLE)
    SET(CMAKE_SHARED_MODULE_SUFFIX ".dylib")
  ENDIF(APPLE)
  SET(ELMERICETEST_CMAKE_NAME "${test_name}_${module_name}")
  ADD_LIBRARY(${ELMERICETEST_CMAKE_NAME} MODULE ${file_name})
  SET_TARGET_PROPERTIES(${ELMERICETEST_CMAKE_NAME}
    PROPERTIES PREFIX "")
  SET_TARGET_PROPERTIES(${ELMERICETEST_CMAKE_NAME}
    PROPERTIES OUTPUT_NAME ${module_name} LINKER_LANGUAGE Fortran)
  TARGET_LINK_LIBRARIES(${ELMERICETEST_CMAKE_NAME} elmersolver)
#  IF(WITH_MPI)
#    ADD_DEPENDENCIES(${ELMERICETEST_CMAKE_NAME} elmersolver)
#  ELSE()
#    ADD_DEPENDENCIES(${ELMERICETEST_CMAKE_NAME} elmersolver)
#  ENDIF()
  UNSET(ELMERICETEST_CMAKE_NAME)
ENDMACRO()

MACRO(RUN_ELMERICE_TEST)
  MESSAGE(STATUS "BINARY_DIR = ${BINARY_DIR}")
  SET(ENV{ELMER_HOME} "${BINARY_DIR}/fem/src")
  SET(ENV{ELMER_LIB} "${BINARY_DIR}/fem/src/modules")
  SET(ENV{ELMER_MODULES_PATH} "${BINARY_DIR}/elmerice/Solvers:${BINARY_DIR}/elmerice/Solvers/GridDataReader:${BINARY_DIR}/elmerice/Solvers/ScatteredDataInterpolator:${BINARY_DIR}/elmerice/Solvers/MeshAdaptation_2D:${BINARY_DIR}/elmerice/UserFunctions")

  IF(WIN32)
    SET(ENV{PATH} "${BINARY_DIR}/elmerice/Solvers;${BINARY_DIR}/elmerice/Utils;${BINARY_DIR}/fem/src;$ENV{PATH}")
    GET_FILENAME_COMPONENT(COMPILER_DIRECTORY ${CMAKE_Fortran_COMPILER} PATH)
    SET(ENV{PATH} "$ENV{ELMER_HOME};$ENV{ELMER_LIB};${BINARY_DIR}/fhutiter/src;${BINARY_DIR}/matc/src;${BINARY_DIR}/mathlibs/src/arpack;${BINARY_DIR}/mathlibs/src/parpack;${COMPILER_DIRECTORY};$ENV{PATH}")
  ENDIF(WIN32)

  # Optional arguments like WITH_MPI
  SET(LIST_VAR "${ARGN}")
  IF(LIST_VAR STREQUAL "")
    FILE(REMOVE "TEST.PASSED")
    EXECUTE_PROCESS(COMMAND ${ELMERSOLVER_BIN}
      OUTPUT_FILE "test-stdout.log"
      ERROR_FILE "test-stderr.log")
  ELSEIF("${LIST_VAR}" STREQUAL "WITH_MPI" AND WITH_MPI)
    # Macro has been called with WITH_MPI argument and MPI is enabled
    SET(N "${NPROCS}")
    IF("${N}" STREQUAL "")
      MESSAGE(FATAL_ERROR "Test failed:variable <NPROC> not defined. Set <NPROC> in runTest.cmake")
    ELSE()
      FILE(REMOVE "TEST.PASSED_${N}")
      EXECUTE_PROCESS(COMMAND "${MPIEXEC}" ${MPIEXEC_NUMPROC_FLAG} ${N} ${MPIEXEC_PREFLAGS} ${ELMERSOLVER_BIN} ${MPIEXEC_POSTFLAGS}
        OUTPUT_FILE "test-stdout.log"
        ERROR_FILE "test-stderr.log")
    ENDIF()
  ENDIF()

  IF(NPROCS GREATER "1")
    FILE(READ "TEST.PASSED_${NPROCS}" RES)
  ELSE()
    FILE(READ "TEST.PASSED" RES)
  ENDIF()
  IF(NOT RES EQUAL "1")
    MESSAGE(FATAL_ERROR "Test failed")
  ENDIF()
ENDMACRO()

MACRO(EXECUTE_ELMER_SOLVER SIFNAME)
  SET(ENV{ELMER_HOME} "${BINARY_DIR}/fem/src")
  SET(ENV{ELMER_LIB} "${BINARY_DIR}/fem/src/modules")
  EXECUTE_PROCESS(COMMAND ${ELMERSOLVER_BIN} ${SIFNAME} OUTPUT_FILE "${SIFNAME}-stdout.log"
    ERROR_FILE "${SIFNAME}-stderr.log")
ENDMACRO()
