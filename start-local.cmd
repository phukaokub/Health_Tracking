@echo off
pushd "%~dp0services\api"
go run .\cmd\dev %*
popd
