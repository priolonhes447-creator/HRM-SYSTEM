# Task: Employee Details Fields + Remove Tagalog Terms

## Status: COMPLETE

## Changes (dashboard.html)
- [x] Remove Tagalog terms from Add/Edit Employee modal labels
- [x] Add new fields (Surname, First Name, Middle Name, Age, Place of Birth, TIN, Civil Status) to the Employee Details (view) modal
- [x] Update `viewEmployee()` to populate the new detail fields
- [x] Update `saveEmployee()` to include the new fields in the payload

## Backend
- [x] database.js already supports age, place_of_birth, tin, civil_status, last_name, first_name, middle_name
- [x] server.js already accepts/stores these fields in POST/PUT /api/employees
