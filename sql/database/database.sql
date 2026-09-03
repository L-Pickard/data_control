USE [master];
GO

IF EXISTS (
        SELECT *
        FROM sys.databases
        WHERE name = 'data_control'
        )
BEGIN
    ALTER DATABASE [data_control]

    SET SINGLE_USER
    WITH

    ROLLBACK IMMEDIATE;

    DROP DATABASE [data_control];

    PRINT 'Database [data_control] dropped.';
END;
GO

CREATE DATABASE [data_control] ON (
    NAME = data_control_data
    ,FILENAME = 'E:\data_control\data_control.mdf'
    ) LOG ON (
    NAME = data_control_log
    ,FILENAME = 'E:\data_control\data_control.ldf'
    );

PRINT 'Database [data_control] created.';