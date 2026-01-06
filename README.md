Opnsense Fireall Scripts with azure vm extension
================================================

## Opnsense NVA VM Single and HA Deploy
- opnsense_scripts/scripts 폴더의 script를 통한 deploy

## Opnsense NVA VM with Azure Gateway Load Balancer
- opnsense_scripts/gwlb_scripts 폴더의 script를 통한 deploy
  
### 유의사항
- Azure Gateway Load Balancer를 사용할경우 백엔드인 Opnsense VM과의 Packet은 Tunnel Interface로 전송됨(vxlan)
- 이 경우 VM NIC의 MTU사이즈 조절이 필요한데 현재 opnsense에서 vm nic가 network accelerated networking이 enable하면 hang이 발생되는 이슈가 있음
  - [Freebsd Hang Issue](https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=285967)
  - 이에 VM SKU의 network accelerated networking를 확인하여 network accelerated networking를 disable할 수 있는지 확인 해야 함
    - 특정 SKU는 network accelerated networking가 Required가 있음(v6 SKU등)
    - [Azure VM SKU List](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/overview?tabs=breakdownseries%2Cgeneralsizelist%2Ccomputesizelist%2Cmemorysizelist%2Cstoragesizelist%2Cgpusizelist%2Cfpgasizelist%2Chpcsizelist)
- Tunnel Interface가 생성될 VM NIC에는 MTU 4000으로 조정되도록 scripts에 반영함
- opnsense에서 vxlan interface(internal, external)에 TCP MSS 조정이 필요하여 1350으로 scripts에 반영함
- vxlan Interface MTU size는 1450임
